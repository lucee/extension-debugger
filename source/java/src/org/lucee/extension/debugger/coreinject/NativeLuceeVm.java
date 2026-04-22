package org.lucee.extension.debugger.coreinject;

import java.lang.ref.Cleaner;
import java.util.ArrayList;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.function.BiConsumer;
import java.util.function.Consumer;

import lucee.runtime.PageContext;
import lucee.runtime.dump.DumpData;
import lucee.runtime.dump.DumpProperties;
import lucee.runtime.dump.DumpUtil;
import lucee.runtime.dump.DumpWriter;
import lucee.runtime.engine.ThreadLocalPageContext;

import org.lucee.extension.debugger.*;
import org.lucee.extension.debugger.coreinject.frame.NativeDebugFrame;
import org.lucee.extension.debugger.strong.DapBreakpointID;
import org.lucee.extension.debugger.strong.CanonicalServerAbsPath;
import org.lucee.extension.debugger.strong.RawIdePath;

/**
 * Native implementation of ILuceeVm that uses only Lucee7+ native debugging APIs.
 * No JDWP connection, no bytecode instrumentation, no agent required.
 *
 * This is for extension-only deployment where luceedebug runs as a Lucee extension
 * rather than a Java agent.
 */
public class NativeLuceeVm implements ILuceeVm {

	private final Config config_;
	private static ClassLoader luceeClassLoader;
	private static final Cleaner cleaner = Cleaner.create();
	private final ValTracker valTracker = new ValTracker(cleaner);

	private Consumer<Long> stepEventCallback = null;
	private BiConsumer<Long, DapBreakpointID> breakpointEventCallback = null;
	private BiConsumer<Long, String> nativeBreakpointEventCallback = null;
	private Consumer<Long> exceptionEventCallback = null;
	private Consumer<Long> pauseEventCallback = null;
	private Consumer<BreakpointsChangedEvent> breakpointsChangedCallback = null;

	private AtomicInteger breakpointID = new AtomicInteger();

	// Cache of frame ID -> frame for scope/variable lookups.
	// Side map tracks which frame IDs belong to each suspended thread so we
	// can evict them on resume — otherwise frameCache grows unbounded and
	// cross-thread iterations hand back stale PCs from prior suspensions.
	private final ConcurrentHashMap<Long, IDebugFrame> frameCache = new ConcurrentHashMap<>();
	private final ConcurrentHashMap<Long, long[]> frameIdsByThreadId = new ConcurrentHashMap<>();

	/**
	 * Set the Lucee classloader for reflection access to Lucee core classes.
	 * Must be called before creating NativeLuceeVm in extension mode.
	 */
	public static void setLuceeClassLoader(ClassLoader cl) {
		luceeClassLoader = cl;
	}

	public NativeLuceeVm(Config config) {
		this.config_ = config;

		// Enable native mode
		NativeDebuggerListener.setNativeMode(true);

		// Register native breakpoint suspend callback
		NativeDebuggerListener.setOnNativeSuspendCallback((javaThreadId, label) -> {
			if (nativeBreakpointEventCallback != null) {
				nativeBreakpointEventCallback.accept(javaThreadId, label);
			}
		});

		// Register native step callback
		NativeDebuggerListener.setOnNativeStepCallback(javaThreadId -> {
			if (stepEventCallback != null) {
				stepEventCallback.accept(javaThreadId);
			}
		});

		// Register native exception callback
		NativeDebuggerListener.setOnNativeExceptionCallback(javaThreadId -> {
			if (exceptionEventCallback != null) {
				exceptionEventCallback.accept(javaThreadId);
			}
		});

		// Register native pause callback
		NativeDebuggerListener.setOnNativePauseCallback(javaThreadId -> {
			if (pauseEventCallback != null) {
				pauseEventCallback.accept(javaThreadId);
			}
		});
	}

	private DapBreakpointID nextDapBreakpointID() {
		return new DapBreakpointID(breakpointID.incrementAndGet());
	}

	// ========== Callback registration ==========

	@Override
	public void registerStepEventCallback(Consumer<Long> cb) {
		stepEventCallback = cb;
	}

	@Override
	public void registerBreakpointEventCallback(BiConsumer<Long, DapBreakpointID> cb) {
		// Not used in native-only mode - native breakpoints don't have JDWP breakpoint IDs
		breakpointEventCallback = cb;
	}

	@Override
	public void registerNativeBreakpointEventCallback(BiConsumer<Long, String> cb) {
		nativeBreakpointEventCallback = cb;
	}

	@Override
	public void registerBreakpointsChangedCallback(Consumer<BreakpointsChangedEvent> cb) {
		breakpointsChangedCallback = cb;
	}

	// ========== Thread operations ==========

	// Virtual thread ID for "All Threads" - used when no specific thread is targeted
	// Thread ID 0 means "all threads" in DAP, but VSCode needs a visible thread to send pause
	// We use 1 as a safe ID that won't conflict with real Java thread IDs (which start much higher)
	private static final long ALL_THREADS_VIRTUAL_ID = 1;

	@Override
	public ThreadInfo[] getThreadListing() {
		var result = new ArrayList<ThreadInfo>();
		var seenThreadIds = new java.util.HashSet<Long>();

		// First, add any suspended threads (these are most important for debugging)
		for (Long threadId : NativeDebuggerListener.getSuspendedThreadIds()) {
			Thread thread = findThreadById(threadId);
			if (thread != null) {
				result.add(new ThreadInfo(thread.getId(), thread.getName() + " (suspended)"));
				seenThreadIds.add(threadId);
			}
		}

		try {
			// CFMLEngineFactory.getInstance() returns the wrapper; unwrap to the impl,
			// which exposes getCFMLFactories(). Mirrors Lucee core's own usage at
			// FDControllerImpl.java:103 in 7.1.
			lucee.loader.engine.CFMLEngineWrapper wrapper = (lucee.loader.engine.CFMLEngineWrapper) lucee.loader.engine.CFMLEngineFactory.getInstance();
			lucee.runtime.engine.CFMLEngineImpl engine = (lucee.runtime.engine.CFMLEngineImpl) wrapper.getEngine();

			for (lucee.runtime.CFMLFactory factory : engine.getCFMLFactories().values()) {
				try {
					for (lucee.runtime.PageContextImpl pc : ((lucee.runtime.CFMLFactoryImpl) factory).getActivePageContexts().values()) {
						Thread thread = pc.getThread();
						if (thread != null && !seenThreadIds.contains(thread.getId())) {
							result.add(new ThreadInfo(thread.getId(), thread.getName()));
							seenThreadIds.add(thread.getId());
						}
					}
				} catch (Exception e) {
					// Skip this factory
				}
			}
		} catch (Exception e) {
			Log.error("Error getting thread listing", e);
		}

		// Always show a virtual "All Threads" entry so VSCode has something to target with pause
		// This allows pause to work even when no specific request thread is visible
		// When paused with this ID, all CFML threads will pause at their next instrumentation point
		if (!seenThreadIds.contains(ALL_THREADS_VIRTUAL_ID)) {
			result.add(0, new ThreadInfo(ALL_THREADS_VIRTUAL_ID, "All CFML Threads"));
		}

		Log.debug("Thread listing: " + result.size() + " threads");
		return result.toArray(new ThreadInfo[0]);
	}

	@Override
	public IDebugFrame[] getStackTrace(long threadID) {
		// In native mode, get frames from the suspended thread's PageContext
		PageContext pc = NativeDebuggerListener.getPageContext(threadID);
		if (pc == null) {
			Log.debug("getStackTrace: no PageContext for thread " + threadID);
			return new IDebugFrame[0];
		}

		// Use NativeDebugFrame to get the CFML stack from PageContext
		// Pass threadID so it can create synthetic frame for top-level code
		IDebugFrame[] frames = NativeDebugFrame.getNativeFrames(pc, valTracker, threadID, luceeClassLoader);
		if (frames == null) {
			Log.debug("getStackTrace: no native frames for thread " + threadID);
			return new IDebugFrame[0];
		}

		// Cache frames for later scope/variable lookups, replacing any frames
		// we cached for a prior suspension of this same thread (a thread can
		// only be suspended at one location at a time).
		evictFramesForThread(threadID);
		long[] ids = new long[frames.length];
		for (int i = 0; i < frames.length; i++) {
			frameCache.put(frames[i].getId(), frames[i]);
			ids[i] = frames[i].getId();
		}
		frameIdsByThreadId.put(threadID, ids);

		Log.trace("getStackTrace: returning " + frames.length + " frames for thread " + threadID);
		return frames;
	}

	/**
	 * Remove this thread's cached frames from frameCache so they can't be
	 * returned to clients (by frameId lookup or iteration) after the thread
	 * has resumed.
	 */
	private void evictFramesForThread(long threadID) {
		long[] ids = frameIdsByThreadId.remove(threadID);
		if (ids != null) {
			for (long id : ids) frameCache.remove(id);
		}
	}

	private Thread findThreadById(long threadId) {
		for (Thread t : Thread.getAllStackTraces().keySet()) {
			if (t.getId() == threadId) {
				return t;
			}
		}
		return null;
	}

	// ========== Variable operations ==========

	@Override
	public IDebugEntity[] getScopes(long frameID) {
		// Look up frame from cache
		IDebugFrame frame = frameCache.get(frameID);
		if (frame == null) {
			Log.debug("getScopes: frame " + frameID + " not found in cache");
			return new IDebugEntity[0];
		}
		return frame.getScopes();
	}

	@Override
	public IDebugEntity[] getVariables(long ID) {
		return getVariablesImpl(ID, null);
	}

	@Override
	public IDebugEntity[] getNamedVariables(long ID) {
		return getVariablesImpl(ID, IDebugEntity.DebugEntityType.NAMED);
	}

	@Override
	public IDebugEntity[] getIndexedVariables(long ID) {
		return getVariablesImpl(ID, IDebugEntity.DebugEntityType.INDEXED);
	}

	private IDebugEntity[] getVariablesImpl(long variablesReference, IDebugEntity.DebugEntityType which) {
		// Look up the object by its variablesReference ID
		var maybeObj = valTracker.maybeGetFromId(variablesReference);
		if (maybeObj.isEmpty()) {
			Log.debug("getVariables: variablesReference " + variablesReference + " not found");
			return new IDebugEntity[0];
		}
		Object obj = maybeObj.get().obj;
		// Get the parent's path and frameId for setVariable support
		String parentPath = valTracker.getPath(variablesReference);
		Long frameId = valTracker.getFrameId(variablesReference);
		return CfValueDebuggerBridge.getAsDebugEntity(valTracker, obj, which, parentPath, frameId);
	}

	// ========== Breakpoint operations ==========

	@Override
	public IBreakpoint[] bindBreakpoints(RawIdePath idePath, CanonicalServerAbsPath serverPath, int[] lines, String[] exprs) {
		// Clear existing native breakpoints for this file
		NativeDebuggerListener.clearBreakpointsForFile(serverPath.get());

		// Get executable lines to validate breakpoints
		int[] executableLines = getExecutableLines(serverPath.get());
		java.util.Set<Integer> validLines = new java.util.HashSet<>();
		for (int line : executableLines) {
			validLines.add(line);
		}

		// Add native breakpoints with optional conditions
		IBreakpoint[] result = new Breakpoint[lines.length];
		for (int i = 0; i < lines.length; i++) {
			String condition = (exprs != null && i < exprs.length) ? exprs[i] : null;
			int requestedLine = lines[i];

			if (validLines.contains(requestedLine)) {
				// Valid executable line - add breakpoint and mark as bound
				NativeDebuggerListener.addBreakpoint(serverPath.get(), requestedLine, condition);
				result[i] = Breakpoint.Bound(requestedLine, nextDapBreakpointID());
			} else {
				// Not an executable line - mark as unbound (unverified)
				result[i] = Breakpoint.Unbound(requestedLine, nextDapBreakpointID());
			}
		}

		return result;
	}

	@Override
	public void clearAllBreakpoints() {
		NativeDebuggerListener.clearAllBreakpoints();
	}

	// ========== Execution control ==========

	@Override
	public void continue_(long threadID) {
		evictFramesForThread(threadID);
		NativeDebuggerListener.resumeNativeThread(threadID);
	}

	@Override
	public void continueAll() {
		frameCache.clear();
		frameIdsByThreadId.clear();
		NativeDebuggerListener.resumeAllNativeThreads();
	}

	@Override
	public void stepIn(long threadID) {
		int currentDepth = getStackDepthForThread(threadID);
		NativeDebuggerListener.startStepping(threadID, StepMode.STEP_INTO, currentDepth);
		continue_(threadID);
	}

	@Override
	public void stepOver(long threadID) {
		int currentDepth = getStackDepthForThread(threadID);
		NativeDebuggerListener.startStepping(threadID, StepMode.STEP_OVER, currentDepth);
		continue_(threadID);
	}

	@Override
	public void stepOut(long threadID) {
		int currentDepth = getStackDepthForThread(threadID);
		NativeDebuggerListener.startStepping(threadID, StepMode.STEP_OUT, currentDepth);
		continue_(threadID);
	}

	/**
	 * Get the current stack depth for a thread using native debugger frames.
	 * Uses NativeDebuggerListener.getStackDepth() to count only real frames (not synthetic).
	 */
	private int getStackDepthForThread(long threadID) {
		PageContext pc = NativeDebuggerListener.getPageContext(threadID);
		return pc != null ? NativeDebuggerListener.getStackDepth(pc) : 0;
	}

	// ========== Debug utilities ==========

	@Override
	public String dump(int dapVariablesReference) {
		return doDumpNative(dapVariablesReference, false);
	}

	@Override
	public String dumpAsJSON(int dapVariablesReference) {
		return doDumpNative(dapVariablesReference, true);
	}

	@Override
	public String getMetadata(int dapVariablesReference) {
		// Get the object from valTracker
		var maybeObj = valTracker.maybeGetFromId(dapVariablesReference);
		if (maybeObj.isEmpty()) {
			return "\"Variable not found\"";
		}
		Object obj = maybeObj.get().obj;

		// Unwrap MarkerTrait.Scope if needed
		if (obj instanceof CfValueDebuggerBridge.MarkerTrait.Scope) {
			obj = ((CfValueDebuggerBridge.MarkerTrait.Scope) obj).scopelike;
		}

		// Get PageContext from a cached frame
		PageContext pc = null;
		Long frameId = valTracker.getFrameId(dapVariablesReference);
		if (frameId != null) {
			IDebugFrame frame = frameCache.get(frameId);
			if (frame instanceof NativeDebugFrame) {
				pc = ((NativeDebugFrame) frame).getPageContext();
			}
		}

		// Fallback: try any suspended frame's PageContext
		if (pc == null) {
			// Fall back to the PC of whichever thread is currently suspended.
			// Can't scan frameCache: may contain stale frames from a prior
			// suspension and would hand back the wrong PC.
			pc = NativeDebuggerListener.getAnySuspendedPageContext();
		}

		if (pc == null) {
			return "\"No PageContext available\"";
		}

		return doGetMetadataWithPageContext(pc, obj);
	}

	/**
	 * Execute getMetadata on a separate thread (required for PageContext registration).
	 */
	private String doGetMetadataWithPageContext(PageContext sourcePC, Object target) {
		final var result = new Object() {
			String value = "\"getMetadata failed\"";
		};

		final PageContext pc = sourcePC;
		final Object obj = target;

		Thread thread = new Thread(() -> {
			try {
				ThreadLocalPageContext.register(pc);
				try {
					// loadBIF with the short function name resolves via Lucee's FunctionLib
					// instead of the OSGi classloader, so we don't need the bundle to
					// self-import lucee.runtime.functions.system.
					lucee.loader.engine.CFMLEngine engine = lucee.loader.engine.CFMLEngineFactory.getInstance();
					lucee.runtime.ext.function.BIF getMetaDataBif = engine.getClassUtil().loadBIF(pc, "getMetaData");
					Object metadata = getMetaDataBif.invoke(pc, new Object[] { obj });

					lucee.runtime.ext.function.BIF serializeJsonBif = engine.getClassUtil().loadBIF(pc, "serializeJSON");
					result.value = (String) serializeJsonBif.invoke(pc, new Object[] { metadata, "struct" });
				} finally {
					ThreadLocalPageContext.release();
				}
			} catch (Throwable e) {
				Log.debug("getMetadata failed: " + e.getMessage());
				result.value = "\"Error: " + e.getMessage().replace("\"", "\\\"") + "\"";
			}
		});

		thread.start();
		try {
			thread.join();
		} catch (InterruptedException e) {
			Thread.currentThread().interrupt();
		}

		return result.value;
	}

	/**
	 * Native mode dump implementation using reflection to call Lucee functions.
	 * @param dapVariablesReference The variablesReference from DAP
	 * @param asJson If true, returns JSON; if false, returns HTML dump
	 */
	private String doDumpNative(int dapVariablesReference, boolean asJson) {
		// Get the object from valTracker
		var maybeObj = valTracker.maybeGetFromId(dapVariablesReference);
		if (maybeObj.isEmpty()) {
			return asJson ? "\"Variable not found\"" : "<div>Variable not found</div>";
		}
		Object obj = maybeObj.get().obj;

		// Unwrap MarkerTrait.Scope if needed
		if (obj instanceof CfValueDebuggerBridge.MarkerTrait.Scope) {
			obj = ((CfValueDebuggerBridge.MarkerTrait.Scope) obj).scopelike;
		}

		// Get the frameId for this variablesReference to get its PageContext
		Long frameId = valTracker.getFrameId(dapVariablesReference);
		PageContext pc = null;
		if (frameId != null) {
			IDebugFrame frame = frameCache.get(frameId);
			if (frame instanceof NativeDebugFrame) {
				pc = ((NativeDebugFrame) frame).getPageContext();
			}
		}

		// If no PageContext from frame, try to find any suspended frame's PageContext
		if (pc == null) {
			// Fall back to the PC of whichever thread is currently suspended.
			// Can't scan frameCache: may contain stale frames from a prior
			// suspension and would hand back the wrong PC.
			pc = NativeDebuggerListener.getAnySuspendedPageContext();
		}

		if (pc == null) {
			return asJson ? "\"No PageContext available\"" : "<div>No PageContext available</div>";
		}

		return doDumpWithPageContext(pc, obj, asJson);
	}

	/**
	 * Execute dump on a separate thread (required for PageContext registration).
	 */
	private String doDumpWithPageContext(PageContext sourcePC, Object someDumpable, boolean asJson) {
		final var result = new Object() {
			String value = asJson ? "\"dump failed\"" : "<div>dump failed</div>";
		};

		final PageContext pc = sourcePC;
		final Object dumpable = someDumpable;

		Thread thread = new Thread(() -> {
			try {
				ThreadLocalPageContext.register(pc);
				try {
					if (asJson) {
						// Resolve via FunctionLib by short name (see doGetMetadataWithPageContext).
						lucee.loader.engine.CFMLEngine engine = lucee.loader.engine.CFMLEngineFactory.getInstance();
						lucee.runtime.ext.function.BIF serializeJsonBif = engine.getClassUtil().loadBIF(pc, "serializeJSON");
						result.value = (String) serializeJsonBif.invoke(pc, new Object[] { dumpable, "struct" });
					} else {
						result.value = wrapDumpInHtmlDoc(dumpObjectAsHtml(pc, dumpable));
					}
				} finally {
					ThreadLocalPageContext.release();
				}
			} catch (Throwable e) {
				Log.debug("dump failed: " + e.getMessage());
				result.value = asJson
					? "\"Error: " + e.getMessage().replace("\"", "\\\"") + "\""
					: "<div>Error: " + e.getMessage() + "</div>";
			}
		});

		thread.start();
		try {
			thread.join();
		} catch (InterruptedException e) {
			Thread.currentThread().interrupt();
		}

		return result.value;
	}

	/**
	 * Dump an object to HTML string using the Lucee loader API.
	 * Mirrors Lucee's own pattern, see ComponentPageImpl.java / InterfacePageImpl.java.
	 */
	private String dumpObjectAsHtml(PageContext pc, Object obj) {
		DumpData dumpData = DumpUtil.toDumpData(obj, pc, 9999, DumpProperties.DEFAULT);
		DumpWriter writer = pc.getConfig().getDefaultDumpWriter(DumpWriter.DEFAULT_RICH);
		return writer.toString(pc, dumpData, true);
	}

	private static String wrapDumpInHtmlDoc(String dumpHtml) {
		return "<!DOCTYPE html>\n" +
			"<html>\n" +
			"<head>\n" +
			"<style>\n" +
			"body { font-family: -apple-system, BlinkMacSystemFont, \"Segoe UI\", Roboto, sans-serif; }\n" +
			"</style>\n" +
			"</head>\n" +
			"<body>\n" +
			dumpHtml +
			"</body>\n" +
			"</html>\n";
	}

	@Override
	public String[] getTrackedCanonicalFileNames() {
		// No class tracking in native mode
		return new String[0];
	}

	@Override
	public String[][] getBreakpointDetail() {
		return NativeDebuggerListener.getBreakpointDetails();
	}

	@Override
	public String getApplicationSettings() {
		// Must read from the suspended-threads map, not frameCache: frameCache
		// accumulates frames across suspensions and would hand back a stale PC
		// whose applicationContext field was never populated (or populated for
		// a different request's app context).
		PageContext pc = NativeDebuggerListener.getAnySuspendedPageContext();
		if (pc == null) {
			return "\"No PageContext available\"";
		}
		return doGetApplicationSettingsWithPageContext(pc);
	}

	/**
	 * Execute getApplicationSettings on a separate thread (required for PageContext registration).
	 */
	private String doGetApplicationSettingsWithPageContext(PageContext sourcePC) {
		final var result = new Object() {
			String value = "\"getApplicationSettings failed\"";
		};

		final PageContext pc = sourcePC;

		Thread thread = new Thread(() -> {
			try {
				ThreadLocalPageContext.register(pc);
				try {
					// Resolve both BIFs via FunctionLib by short name; matches the dump/metadata paths.
					lucee.loader.engine.CFMLEngine engine = lucee.loader.engine.CFMLEngineFactory.getInstance();

					lucee.runtime.ext.function.BIF getAppSettingsBif = engine.getClassUtil().loadBIF(pc, "getApplicationSettings");
					Object settings = getAppSettingsBif.invoke(pc, new Object[] {});

					lucee.runtime.ext.function.BIF serializeJsonBif = engine.getClassUtil().loadBIF(pc, "serializeJSON");
					result.value = (String) serializeJsonBif.invoke(pc, new Object[] { settings, "struct" });
				} finally {
					ThreadLocalPageContext.release();
				}
			} catch (Throwable e) {
				Log.debug("getApplicationSettings failed: " + e.getMessage());
				result.value = "\"Error: " + e.getMessage().replace("\"", "\\\"") + "\"";
			}
		});

		thread.start();
		try {
			thread.join(5000); // 5 second timeout
		} catch (InterruptedException e) {
			return "\"Timeout getting application settings\"";
		}

		return result.value;
	}

	@Override
	public String getSourcePathForVariablesRef(int variablesRef) {
		return valTracker
			.maybeGetFromId(variablesRef)
			.map(taggedObj -> CfValueDebuggerBridge.getSourcePath(taggedObj.obj))
			.orElse(null);
	}

	@Override
	public org.eclipse.lsp4j.debug.CompletionItem[] getCompletions(int frameId, String partialExpr) {
		// Get PageContext from frame or any suspended frame
		PageContext pc = null;
		IDebugFrame frame = frameCache.get((long) frameId);
		if (frame instanceof NativeDebugFrame) {
			pc = ((NativeDebugFrame) frame).getPageContext();
		}
		if (pc == null) {
			// Same rationale as the other fallback sites — use the suspend
			// map, not frameCache, to avoid stale PCs from earlier suspensions.
			pc = NativeDebuggerListener.getAnySuspendedPageContext();
		}

		if (pc == null) {
			return new org.eclipse.lsp4j.debug.CompletionItem[0];
		}

		return doGetCompletionsWithPageContext(pc, partialExpr);
	}

	private org.eclipse.lsp4j.debug.CompletionItem[] doGetCompletionsWithPageContext(PageContext pc, String partialExpr) {
		final java.util.List<org.eclipse.lsp4j.debug.CompletionItem> results = new java.util.ArrayList<>();

		try {
			ClassLoader cl = luceeClassLoader != null ? luceeClassLoader : pc.getClass().getClassLoader();

			// Parse the expression: "local.foo.ba" -> base="local.foo", prefix="ba"
			// Or just "va" -> base=null, prefix="va"
			String base = null;
			String prefix = partialExpr.toLowerCase();
			int lastDot = partialExpr.lastIndexOf('.');

			if (lastDot > 0) {
				base = partialExpr.substring(0, lastDot);
				prefix = partialExpr.substring(lastDot + 1).toLowerCase();
			}

			if (base != null) {
				// Evaluate the base to get keys.
				// Note: Evaluate implements Function, not BIF — must go through reflection
				// rather than engine.getClassUtil().loadBIF(pc, "evaluate").
				try {
					Class<?> evaluateClass = cl.loadClass("lucee.runtime.functions.dynamicEvaluation.Evaluate");
					java.lang.reflect.Method callMethod = evaluateClass.getMethod("call", PageContext.class, Object[].class);

					ThreadLocalPageContext.register(pc);
					try {
						Object result = callMethod.invoke(null, pc, new Object[]{base});
						if (result instanceof java.util.Map) {
							@SuppressWarnings("unchecked")
							java.util.Map<Object, Object> map = (java.util.Map<Object, Object>) result;
							for (Object key : map.keySet()) {
								String keyStr = String.valueOf(key);
								if (keyStr.toLowerCase().startsWith(prefix)) {
									var item = new org.eclipse.lsp4j.debug.CompletionItem();
									item.setLabel(keyStr);
									item.setType(org.eclipse.lsp4j.debug.CompletionItemType.PROPERTY);
									results.add(item);
								}
							}
						}
					} finally {
						ThreadLocalPageContext.release();
					}
				} catch (Exception e) {
					// Evaluation failed, return empty
					Log.debug("Completion evaluation failed: " + e.getMessage());
				}
			} else {
				// No base - complete from scope names and top-level scope variables
				String[] scopes = {"variables", "local", "arguments", "form", "url", "cgi", "cookie", "session", "application", "server", "request", "this"};
				for (String scope : scopes) {
					if (scope.toLowerCase().startsWith(prefix)) {
						var item = new org.eclipse.lsp4j.debug.CompletionItem();
						item.setLabel(scope);
						item.setType(org.eclipse.lsp4j.debug.CompletionItemType.MODULE);
						results.add(item);
					}
				}

				// Also try to complete from variables scope
				try {
					Object variablesScope = pc.variablesScope();
					if (variablesScope instanceof java.util.Map) {
						@SuppressWarnings("unchecked")
						java.util.Map<Object, Object> map = (java.util.Map<Object, Object>) variablesScope;
						for (Object key : map.keySet()) {
							String keyStr = String.valueOf(key);
							if (keyStr.toLowerCase().startsWith(prefix)) {
								var item = new org.eclipse.lsp4j.debug.CompletionItem();
								item.setLabel(keyStr);
								item.setType(org.eclipse.lsp4j.debug.CompletionItemType.VARIABLE);
								results.add(item);
							}
						}
					}
				} catch (Exception e) {
					// Ignore scope access errors
				}
			}
		} catch (Exception e) {
			Log.debug("Completion failed: " + e.getMessage());
		}

		// Sort by label and limit
		results.sort((a, b) -> a.getLabel().compareToIgnoreCase(b.getLabel()));

		Log.debug("Completions for '" + partialExpr + "': returning " + results.size() + " items");
		for (var item : results) {
			Log.debug("  - " + item.getLabel());
		}

		if (results.size() > 100) {
			return results.subList(0, 100).toArray(new org.eclipse.lsp4j.debug.CompletionItem[0]);
		}
		return results.toArray(new org.eclipse.lsp4j.debug.CompletionItem[0]);
	}

	@Override
	public Either<String, Either<ICfValueDebuggerBridge, String>> evaluate(int frameID, String expr) {
		// For native mode, use the frame's PageContext to evaluate expressions
		IDebugFrame frame = frameCache.get((long) frameID);
		if (frame == null) {
			return Either.Left("Frame not found: " + frameID);
		}

		if (!(frame instanceof NativeDebugFrame)) {
			// Fall back to JDWP mode if available
			if (GlobalIDebugManagerHolder.debugManager != null) {
				return GlobalIDebugManagerHolder.debugManager.evaluate((Long)(long)frameID, expr);
			}
			return Either.Left("evaluate only supported for native frames");
		}

		NativeDebugFrame nativeFrame = (NativeDebugFrame) frame;
		PageContext pc = nativeFrame.getPageContext();
		if (pc == null) {
			return Either.Left("No PageContext available for frame");
		}

		try {
			// Evaluate implements Function, not BIF — use reflection rather than loadBIF.
			ClassLoader cl = luceeClassLoader != null ? luceeClassLoader : pc.getClass().getClassLoader();
			Class<?> evaluateClass = cl.loadClass("lucee.runtime.functions.dynamicEvaluation.Evaluate");
			java.lang.reflect.Method callMethod = evaluateClass.getMethod("call", PageContext.class, Object[].class);

			ThreadLocalPageContext.register(pc);

			try {
				Object result = callMethod.invoke(null, pc, new Object[]{expr});

				if (result == null) {
					return Either.Right(Either.Right("null"));
				} else if (result instanceof String) {
					return Either.Right(Either.Right("\"" + ((String)result).replaceAll("\"", "\\\\\"") + "\""));
				} else if (result instanceof Number || result instanceof Boolean) {
					return Either.Right(Either.Right(result.toString()));
				} else {
					CfValueDebuggerBridge bridge = new CfValueDebuggerBridge(valTracker, result);
					return Either.Right(Either.Left(bridge));
				}
			} finally {
				ThreadLocalPageContext.release();
			}
		} catch (Throwable e) {
			Throwable cause = e;
			if (e instanceof java.lang.reflect.InvocationTargetException && e.getCause() != null) {
				cause = e.getCause();
			}
			String msg = cause.getMessage();
			if (msg == null) {
				msg = cause.getClass().getName();
			}
			return Either.Left("Evaluation error: " + msg);
		}
	}

	@Override
	public Either<String, Either<ICfValueDebuggerBridge, String>> setVariable(long variablesReference, String name, String value, long frameIdHint) {
		// Get the frame to access PageContext
		// First try using the frameId from ValTracker (associated with the variablesReference)
		Long trackedFrameId = valTracker.getFrameId(variablesReference);
		long actualFrameId = (trackedFrameId != null) ? trackedFrameId : frameIdHint;

		IDebugFrame frame = frameCache.get(actualFrameId);
		if (frame == null) {
			return Either.Left("Frame not found: " + actualFrameId);
		}

		if (!(frame instanceof NativeDebugFrame)) {
			return Either.Left("setVariable only supported for native frames");
		}

		NativeDebugFrame nativeFrame = (NativeDebugFrame) frame;
		PageContext pc = nativeFrame.getPageContext();
		if (pc == null) {
			return Either.Left("No PageContext available for frame");
		}

		// Get the parent path from ValTracker
		String parentPath = valTracker.getPath(variablesReference);
		if (parentPath == null) {
			return Either.Left("Cannot determine variable path for variablesReference: " + variablesReference);
		}

		// Build the full variable path
		String fullPath = parentPath + "." + name;
		Log.debug("setVariable: " + fullPath + " = " + value);

		try {
			// Evaluate implements Function, not BIF — use reflection rather than loadBIF.
			ClassLoader cl = luceeClassLoader != null ? luceeClassLoader : pc.getClass().getClassLoader();
			Class<?> evaluateClass = cl.loadClass("lucee.runtime.functions.dynamicEvaluation.Evaluate");
			java.lang.reflect.Method callMethod = evaluateClass.getMethod("call", PageContext.class, Object[].class);

			ThreadLocalPageContext.register(pc);

			try {
				// First, evaluate the value expression to get the actual object
				Object evaluatedValue = callMethod.invoke(null, pc, new Object[]{value});

				// Use Lucee's setVariable to set the value
				Object result = pc.setVariable(fullPath, evaluatedValue);

				// Return the result as a debug entity
				if (result == null) {
					return Either.Right(Either.Right("null"));
				} else if (result instanceof String) {
					return Either.Right(Either.Right("\"" + ((String)result).replaceAll("\"", "\\\\\"") + "\""));
				} else if (result instanceof Number || result instanceof Boolean) {
					return Either.Right(Either.Right(result.toString()));
				} else {
					// Complex object - wrap it for display
					CfValueDebuggerBridge bridge = new CfValueDebuggerBridge(valTracker, result);
					return Either.Right(Either.Left(bridge));
				}
			} finally {
				ThreadLocalPageContext.release();
			}
		} catch (Throwable e) {
			// Unwrap InvocationTargetException to get the real cause
			Throwable cause = e;
			if (e instanceof java.lang.reflect.InvocationTargetException && e.getCause() != null) {
				cause = e.getCause();
			}
			String msg = cause.getMessage();
			if (msg == null) {
				msg = cause.getClass().getName();
			}
			Log.debug("setVariable failed: " + msg);
			return Either.Left("Error setting variable: " + msg);
		}
	}

	@Override
	public void registerExceptionEventCallback(Consumer<Long> cb) {
		exceptionEventCallback = cb;
	}

	@Override
	public void registerPauseEventCallback(Consumer<Long> cb) {
		pauseEventCallback = cb;
	}

	@Override
	public void pause(long threadID) {
		NativeDebuggerListener.requestPause(threadID);
	}

	@Override
	public Throwable getExceptionForThread(long threadId) {
		NativeDebuggerListener.SuspendLocation loc = NativeDebuggerListener.getSuspendLocation(threadId);
		return loc != null ? loc.exception : null;
	}

	/**
	 * Get executable line numbers for a file.
	 * Used by DAP breakpointLocations request.
	 *
	 * @param serverPath The server-side absolute file path
	 * @return Array of line numbers where breakpoints can be set
	 */
	public int[] getExecutableLines(String serverPath) {
		return NativeDebuggerListener.getExecutableLines(serverPath);
	}
}
