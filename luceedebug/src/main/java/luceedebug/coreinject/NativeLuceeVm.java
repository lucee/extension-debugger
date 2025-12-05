package luceedebug.coreinject;

import java.lang.ref.Cleaner;
import java.util.ArrayList;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.function.BiConsumer;
import java.util.function.Consumer;

import lucee.runtime.PageContext;

import luceedebug.*;
import luceedebug.coreinject.frame.NativeDebugFrame;
import luceedebug.strong.DapBreakpointID;
import luceedebug.strong.CanonicalServerAbsPath;
import luceedebug.strong.RawIdePath;

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

	// Cache of frame ID -> frame for scope/variable lookups
	private final ConcurrentHashMap<Long, IDebugFrame> frameCache = new ConcurrentHashMap<>();

	/**
	 * Set the Lucee classloader for reflection access to Lucee core classes.
	 * Must be called before creating NativeLuceeVm in extension mode.
	 */
	public static void setLuceeClassLoader(ClassLoader cl) {
		luceeClassLoader = cl;
	}

	public NativeLuceeVm(Config config) {
		this.config_ = config;

		// Enable native-only mode
		NativeDebuggerListener.setNativeOnlyMode(true);

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
			// Get CFMLEngine via the loader's factory (available to extension classloader)
			Object engine = lucee.loader.engine.CFMLEngineFactory.getInstance();

			// The factory returns CFMLEngineWrapper - unwrap to get CFMLEngineImpl
			java.lang.reflect.Method getEngineMethod = engine.getClass().getMethod("getEngine");
			Object engineImpl = getEngineMethod.invoke(engine);

			// Get all CFMLFactory instances from the engine impl
			// CFMLEngineImpl has getCFMLFactories() returning Map<String, CFMLFactory>
			java.lang.reflect.Method getFactoriesMethod = engineImpl.getClass().getMethod("getCFMLFactories");
			@SuppressWarnings("unchecked")
			java.util.Map<String, ?> factoriesMap = (java.util.Map<String, ?>) getFactoriesMethod.invoke(engineImpl);
			Object[] factories = factoriesMap.values().toArray();

			for (Object factory : factories) {
				try {
					// Call getActivePageContexts() - it's in CFMLFactoryImpl
					java.lang.reflect.Method getActiveMethod = factory.getClass().getMethod("getActivePageContexts");
					@SuppressWarnings("unchecked")
					java.util.Map<Integer, ?> activeContexts = (java.util.Map<Integer, ?>) getActiveMethod.invoke(factory);

					// Each PageContext has a getThread() method
					for (Object pc : activeContexts.values()) {
						try {
							java.lang.reflect.Method getThreadMethod = pc.getClass().getMethod("getThread");
							Thread thread = (Thread) getThreadMethod.invoke(pc);
							if (thread != null && !seenThreadIds.contains(thread.getId())) {
								result.add(new ThreadInfo(thread.getId(), thread.getName()));
								seenThreadIds.add(thread.getId());
							}
						} catch (Exception e) {
							// Skip this context if we can't get its thread
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

		// Cache frames for later scope/variable lookups
		for (IDebugFrame frame : frames) {
			frameCache.put(frame.getId(), frame);
		}

		Log.trace("getStackTrace: returning " + frames.length + " frames for thread " + threadID);
		return frames;
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
		return CfValueDebuggerBridge.getAsDebugEntity(valTracker, obj, which);
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
		NativeDebuggerListener.resumeNativeThread(threadID);
	}

	@Override
	public void continueAll() {
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
	 */
	private int getStackDepthForThread(long threadID) {
		IDebugFrame[] frames = getStackTrace(threadID);
		return frames != null ? frames.length : 0;
	}

	// ========== Debug utilities ==========

	@Override
	public String dump(int dapVariablesReference) {
		// Need a suspended thread to get PageContext for dump
		// For native mode, we'd need to track suspended threads differently
		return GlobalIDebugManagerHolder.debugManager.doDump(new ArrayList<>(), dapVariablesReference);
	}

	@Override
	public String dumpAsJSON(int dapVariablesReference) {
		return GlobalIDebugManagerHolder.debugManager.doDumpAsJSON(new ArrayList<>(), dapVariablesReference);
	}

	@Override
	public String[] getTrackedCanonicalFileNames() {
		// No class tracking in native mode
		return new String[0];
	}

	@Override
	public String[][] getBreakpointDetail() {
		// TODO: Return native breakpoint details
		return new String[0][];
	}

	@Override
	public String getSourcePathForVariablesRef(int variablesRef) {
		return GlobalIDebugManagerHolder.debugManager.getSourcePathForVariablesRef(variablesRef);
	}

	@Override
	public Either<String, Either<ICfValueDebuggerBridge, String>> evaluate(int frameID, String expr) {
		// In native mode, GlobalIDebugManagerHolder.debugManager is null
		// TODO: Implement native evaluation using PageContext
		if (GlobalIDebugManagerHolder.debugManager == null) {
			return Either.Left("Expression evaluation not yet supported in native debugger mode");
		}
		return GlobalIDebugManagerHolder.debugManager.evaluate((Long)(long)frameID, expr);
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
