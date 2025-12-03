package luceedebug.extension;

import java.lang.reflect.Method;

import lucee.loader.engine.CFMLEngineFactory;
import lucee.runtime.config.Config;

import luceedebug.DapServer;
import luceedebug.coreinject.NativeLuceeVm;
import luceedebug.coreinject.NativeDebuggerListener;

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
		System.out.println("[luceedebug] Extension activating via startup-hook");

		// Get debug port from environment - if not set, debugger is disabled
		int debugPort = getDebuggerPort();
		if (debugPort < 0) {
			System.out.println("[luceedebug] Debugger not enabled");
			System.out.println("[luceedebug] Set LUCEE_DEBUGGER_PORT=<port> to enable");
			return;
		}

		// Get classloaders - extension's loader has our classes, Lucee's has core interfaces
		ClassLoader extensionLoader = this.getClass().getClassLoader();
		ClassLoader luceeLoader = luceeConfig.getClass().getClassLoader();

		// Register debugger listener with Lucee's DebuggerRegistry
		if (!registerNativeDebuggerListener(luceeLoader, extensionLoader)) {
			System.out.println("[luceedebug] Failed to register debugger listener - extension disabled");
			return;
		}

		// Determine filesystem case sensitivity from Lucee's config location
		String configPath = luceeConfig.getConfigDir().getAbsolutePath();
		boolean fsCaseSensitive = luceedebug.Config.checkIfFileSystemIsCaseSensitive(configPath);

		// Create luceedebug config
		luceedebug.Config config = new luceedebug.Config(fsCaseSensitive);

		// Create NativeLuceeVm
		luceeVm = new NativeLuceeVm(config);

		// Start DAP server in background thread (createForSocket blocks forever)
		final int port = debugPort;
		new Thread(() -> {
			DapServer.createForSocket(luceeVm, config, "localhost", port);
		}, "luceedebug-dap-server").start();

		System.out.println("[luceedebug] DAP server starting on localhost:" + debugPort);
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

			// Create proxy in Lucee's classloader, delegating to extension's implementation
			Object listenerProxy = java.lang.reflect.Proxy.newProxyInstance(
				luceeLoader,
				new Class<?>[] { listenerInterface },
				(proxy, method, args) -> {
					switch (method.getName()) {
						case "onSuspend": return onSuspendMethod.invoke(null, args);
						case "onResume": return onResumeMethod.invoke(null, args);
						case "shouldSuspend": return shouldSuspendMethod.invoke(null, args);
						default: throw new UnsupportedOperationException("Unknown method: " + method.getName());
					}
				}
			);

			// Register with Lucee
			Method setListener = registryClass.getMethod("setListener", listenerInterface);
			setListener.invoke(null, listenerProxy);

			System.out.println("[luceedebug] Registered native debugger listener");
			return true;
		} catch (ClassNotFoundException e) {
			System.out.println("[luceedebug] DebuggerRegistry not found - requires Lucee 7.1+");
			return false;
		} catch (Throwable e) {
			System.out.println("[luceedebug] Failed to register listener: " + e.getMessage());
			e.printStackTrace();
			return false;
		}
	}

	/**
	 * Get debugger port from environment/system property.
	 * Returns -1 if not set (debugger disabled).
	 */
	private static int getDebuggerPort() {
		String port = getSystemPropOrEnvVar("lucee.debugger.port");
		if (port == null || port.isEmpty()) {
			return -1; // disabled
		}
		return CFMLEngineFactory.getInstance().getCastUtil().toIntValue(port, -1);
	}

	/**
	 * Get system property or environment variable.
	 * System property takes precedence. Env var name is derived from property name
	 * by uppercasing and replacing dots with underscores.
	 */
	private static String getSystemPropOrEnvVar(String propertyName) {
		// Try system property first
		String value = System.getProperty(propertyName);
		if (value != null && !value.isEmpty()) {
			return value;
		}
		// Try env var (lucee.debugger.port -> LUCEE_DEBUGGER_PORT)
		String envName = propertyName.toUpperCase().replace('.', '_');
		return System.getenv(envName);
	}
}
