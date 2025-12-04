package luceedebug.extension;

import java.lang.reflect.Method;

import lucee.runtime.config.Config;

import luceedebug.DapServer;
import luceedebug.EnvUtil;
import luceedebug.Log;
import luceedebug.coreinject.NativeLuceeVm;

/**
 * Extension startup hook - instantiated by Lucee when the extension loads.
 * Uses Lucee's startup-hook mechanism (manifest attribute).
 *
 * Native-only mode: requires Lucee 7.1+ with DebuggerRegistry API.
 * No JDWP, no Java agent, no bytecode instrumentation.
 */
public class ExtensionActivator {
	private static NativeLuceeVm luceeVm;

	/**
	 * Constructor called by Lucee's startup-hook mechanism.
	 * Lucee passes the Config object automatically.
	 */
	public ExtensionActivator(Config luceeConfig) {
		Log.info("Extension activating via startup-hook");

		// Get debug port from environment - if not set, debugger is disabled
		int debugPort = EnvUtil.getDebuggerPort();
		if (debugPort < 0) {
			Log.info("Debugger not enabled");
			Log.info("Set LUCEE_DEBUGGER_PORT=<port> to enable");
			return;
		}

		// Get classloaders - extension's loader has our classes, Lucee's has core interfaces
		ClassLoader extensionLoader = this.getClass().getClassLoader();
		ClassLoader luceeLoader = luceeConfig.getClass().getClassLoader();

		// Log execution logging status - this determines if breakpoints work
		if (EnvUtil.isDebuggerEnabled()) {
			Log.info("Execution logging: ENABLED (LUCEE_DEBUGGER_ENABLED=true)");
		} else {
			Log.info("Execution logging: DISABLED (set LUCEE_DEBUGGER_ENABLED=true to enable breakpoints)");
		}

		// Register debugger listener with Lucee's DebuggerRegistry
		if (!registerNativeDebuggerListener(luceeLoader, extensionLoader)) {
			Log.error("Failed to register debugger listener - extension disabled");
			return;
		}

		// Determine filesystem case sensitivity from Lucee's config location
		String configPath = luceeConfig.getConfigDir().getAbsolutePath();
		boolean fsCaseSensitive = luceedebug.Config.checkIfFileSystemIsCaseSensitive(configPath);

		// Create luceedebug config
		luceedebug.Config config = new luceedebug.Config(fsCaseSensitive);

		// Set Lucee classloader for reflection access to core classes
		NativeLuceeVm.setLuceeClassLoader(luceeLoader);

		// Create NativeLuceeVm
		luceeVm = new NativeLuceeVm(config);

		// Start DAP server in background thread (createForSocket blocks forever)
		final int port = debugPort;
		new Thread(() -> {
			DapServer.createForSocket(luceeVm, config, "localhost", port);
		}, "luceedebug-dap-server").start();

		Log.info("DAP server starting on localhost:" + debugPort);
	}

	/**
	 * Enable DebuggerExecutionLog via ConfigAdmin.
	 * This triggers template recompilation with exeLogStart()/exeLogEnd() bytecode
	 * which calls DebuggerRegistry.shouldSuspend() on each line.
	 *
	 * Note: During startup-hook, we receive ConfigServer (not ConfigWeb).
	 * We need to find a ConfigAdmin.newInstance() method that works with ConfigServer.
	 */
	private void enableDebuggerExecutionLog(Config luceeConfig, ClassLoader luceeLoader) {
		try {
			// Load ConfigAdmin class from Lucee core
			Class<?> configAdminClass = luceeLoader.loadClass("lucee.runtime.config.ConfigAdmin");
			Class<?> classDefClass = luceeLoader.loadClass("lucee.runtime.db.ClassDefinition");
			Class<?> classDefImplClass = luceeLoader.loadClass("lucee.transformer.library.ClassDefinitionImpl");
			Class<?> structClass = luceeLoader.loadClass("lucee.runtime.type.Struct");
			Class<?> structImplClass = luceeLoader.loadClass("lucee.runtime.type.StructImpl");

			// Find the right newInstance method - try different signatures
			Object configAdmin = null;

			// Try to find a method that accepts our config type
			for (Method m : configAdminClass.getMethods()) {
				if (m.getName().equals("newInstance") && m.getParameterCount() >= 2) {
					Class<?>[] params = m.getParameterTypes();
					// Look for (Config/ConfigServer, String/Password, boolean) or similar
					if (params[0].isAssignableFrom(luceeConfig.getClass())) {
						try {
							if (params.length == 2) {
								// (Config, Password)
								configAdmin = m.invoke(null, luceeConfig, null);
							} else if (params.length == 3 && params[2] == boolean.class) {
								// (Config, Password, optionalPW)
								configAdmin = m.invoke(null, luceeConfig, null, true);
							}
							if (configAdmin != null) {
								Log.info("Created ConfigAdmin using " + m);
								break;
							}
						} catch (Exception e) {
							// Try next method
						}
					}
				}
			}

			if (configAdmin == null) {
				Log.error("Could not create ConfigAdmin - no compatible newInstance method found");
				Log.info("Available newInstance methods:");
				for (Method m : configAdminClass.getMethods()) {
					if (m.getName().equals("newInstance")) {
						Log.info("  " + m);
					}
				}
				return;
			}

			// Create ClassDefinition for DebuggerExecutionLog
			java.lang.reflect.Constructor<?> cdConstructor = classDefImplClass.getConstructor(String.class);
			Object classDefinition = cdConstructor.newInstance("lucee.runtime.engine.DebuggerExecutionLog");

			// Create empty Struct for arguments
			Object emptyStruct = structImplClass.getConstructor().newInstance();

			// admin.updateExecutionLog(classDefinition, arguments, enabled=true)
			Method updateMethod = configAdminClass.getMethod("updateExecutionLog",
				classDefClass, structClass, boolean.class);
			updateMethod.invoke(configAdmin, classDefinition, emptyStruct, true);

			// Persist and reload config - this triggers template recompilation
			Method storeMethod = configAdminClass.getMethod("storeAndReload");
			storeMethod.invoke(configAdmin);

			Log.info("Enabled DebuggerExecutionLog - templates will recompile with debugger bytecode");
		} catch (ClassNotFoundException e) {
			Log.error("ConfigAdmin not found - cannot enable execution log: " + e.getMessage());
		} catch (Throwable e) {
			Log.error("Failed to enable execution log", e);
		}
	}

	/**
	 * Register native debugger listener using cross-classloader proxy.
	 * DebuggerRegistry and DebuggerListener are in Lucee's core (luceeLoader).
	 * NativeDebuggerListener is in our extension bundle (extensionLoader).
	 */
	private boolean registerNativeDebuggerListener(ClassLoader luceeLoader, ClassLoader extensionLoader) {
		try {
			// Load Lucee core classes
			Class<?> registryClass = luceeLoader.loadClass("lucee.runtime.debug.DebuggerRegistry");
			Class<?> listenerInterface = luceeLoader.loadClass("lucee.runtime.debug.DebuggerListener");
			Class<?> pageContextClass = luceeLoader.loadClass("lucee.runtime.PageContext");

			// Load our implementation from extension bundle
			Class<?> nativeListenerClass = extensionLoader.loadClass(
				"luceedebug.coreinject.NativeDebuggerListener");

			// Cache method lookups
			final Method onSuspendMethod = nativeListenerClass.getMethod("onSuspend",
				pageContextClass, String.class, int.class, String.class);
			final Method onResumeMethod = nativeListenerClass.getMethod("onResume", pageContextClass);
			final Method shouldSuspendMethod = nativeListenerClass.getMethod("shouldSuspend",
				pageContextClass, String.class, int.class);
			final Method isDapClientConnectedMethod = nativeListenerClass.getMethod("isDapClientConnected");
			final Method onExceptionMethod = nativeListenerClass.getMethod("onException",
				pageContextClass, Throwable.class, boolean.class);

			// Create proxy in Lucee's classloader, delegating to extension's implementation
			Object listenerProxy = java.lang.reflect.Proxy.newProxyInstance(
				luceeLoader,
				new Class<?>[] { listenerInterface },
				(proxy, method, args) -> {
					switch (method.getName()) {
						case "isActive": return isDapClientConnectedMethod.invoke(null);
						case "onSuspend": return onSuspendMethod.invoke(null, args);
						case "onResume": return onResumeMethod.invoke(null, args);
						case "shouldSuspend": return shouldSuspendMethod.invoke(null, args);
						case "onException": return onExceptionMethod.invoke(null, args);
						default: return null; // Default methods like onException have defaults
					}
				}
			);

			// Register with Lucee
			Method setListener = registryClass.getMethod("setListener", listenerInterface);
			setListener.invoke(null, listenerProxy);

			Log.info("Registered native debugger listener");
			return true;
		} catch (ClassNotFoundException e) {
			Log.info("DebuggerRegistry not found - requires Lucee 7.1+");
			return false;
		} catch (Throwable e) {
			Log.error("Failed to register listener", e);
			return false;
		}
	}

	/**
	 * Called by Lucee when the extension is uninstalled or updated.
	 * Shuts down the DAP server to free the port.
	 */
	public void finalize() {
		Log.info("Extension finalizing - shutting down DAP server");
		DapServer.shutdown();
	}
}
