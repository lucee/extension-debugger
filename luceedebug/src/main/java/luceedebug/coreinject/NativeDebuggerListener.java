package luceedebug.coreinject;

import java.lang.ref.WeakReference;
import java.util.concurrent.ConcurrentHashMap;
import java.util.function.BiConsumer;
import java.util.function.Consumer;

import lucee.runtime.PageContext;
import luceedebug.Config;
import luceedebug.Log;

/**
 * Step mode for stepping operations.
 */
enum StepMode {
	NONE,
	STEP_INTO,
	STEP_OVER,
	STEP_OUT
}

/**
 * Implementation of Lucee's DebuggerListener interface for native breakpoint support.
 * This allows luceedebug to receive suspend/resume callbacks and manage breakpoints
 * without JDWP instrumentation.
 *
 * Note: This class implements the interface via reflection since it's in Lucee core,
 * not in the loader. We create a dynamic proxy that forwards calls to this class.
 *
 * TODO: Consider using DAP OutputEvent to show debug messages in VS Code Debug Console
 * instead of System.out.println. This would give users visibility into native breakpoint
 * activity within the IDE.
 */
public class NativeDebuggerListener {

	/**
	 * Map of "file:line" -> true for active breakpoints.
	 * Uses ConcurrentHashMap for thread-safe access from multiple request threads.
	 */
	private static final ConcurrentHashMap<String, Boolean> breakpoints = new ConcurrentHashMap<>();

	/**
	 * Map of "file:line" -> condition expression for conditional breakpoints.
	 * If a breakpoint has no condition, it won't have an entry here.
	 */
	private static final ConcurrentHashMap<String, String> breakpointConditions = new ConcurrentHashMap<>();

	/**
	 * Map of Java thread ID -> WeakReference<PageContext> for natively suspended threads.
	 * Used to call debuggerResume() when DAP continue is received.
	 * Note: We use PageContext (loader interface) not PageContextImpl to avoid class loading cycles.
	 */
	private static final ConcurrentHashMap<Long, WeakReference<PageContext>> nativelySuspendedThreads = new ConcurrentHashMap<>();

	/**
	 * Suspend location info for threads (file and line where suspended).
	 * Used when there are no native DebuggerFrames (top-level code).
	 */
	private static final ConcurrentHashMap<Long, SuspendLocation> suspendLocations = new ConcurrentHashMap<>();

	/**
	 * Simple holder for file/line/label at suspend point.
	 */
	public static class SuspendLocation {
		public final String file;
		public final int line;
		public final String label;
		public final Throwable exception; // non-null if suspended due to exception
		public SuspendLocation( String file, int line, String label ) {
			this( file, line, label, null );
		}
		public SuspendLocation( String file, int line, String label, Throwable exception ) {
			this.file = file;
			this.line = line;
			this.label = label;
			this.exception = exception;
		}
	}

	/**
	 * Pending exception for a thread - stored when onException returns true,
	 * then consumed when onSuspend is called.
	 */
	private static final ConcurrentHashMap<Long, Throwable> pendingExceptions = new ConcurrentHashMap<>();

	/**
	 * Callback to notify LuceeVm when a thread suspends via native breakpoint.
	 * Called with Java thread ID and optional label. Used for "breakpoint" stop reason in DAP.
	 * Label is non-null for programmatic breakpoint("label") calls, null otherwise.
	 */
	private static volatile BiConsumer<Long, String> onNativeSuspendCallback = null;

	/**
	 * Callback to notify LuceeVm when a thread stops after a step.
	 * Called with Java thread ID. Used for "step" stop reason in DAP.
	 */
	private static volatile Consumer<Long> onNativeStepCallback = null;

	/**
	 * Flag to indicate native-only mode (no JDWP breakpoints).
	 * When true, only native breakpoints are used.
	 */
	private static volatile boolean nativeOnlyMode = false;

	/**
	 * Flag indicating a DAP client is actually connected.
	 * Set to true when DAP client connects, false when it disconnects.
	 * Distinct from callbacks being registered (which happens at extension startup).
	 */
	private static volatile boolean dapClientConnected = false;

	/**
	 * Flag to break on uncaught exceptions.
	 * Set via DAP setExceptionBreakpoints request.
	 */
	private static volatile boolean breakOnUncaughtExceptions = false;

	/**
	 * Per-thread stepping state.
	 */
	private static final ConcurrentHashMap<Long, StepState> steppingThreads = new ConcurrentHashMap<>();

	/**
	 * Stepping state for a single thread.
	 */
	private static class StepState {
		final StepMode mode;
		final int startDepth;

		StepState(StepMode mode, int startDepth) {
			this.mode = mode;
			this.startDepth = startDepth;
		}
	}

	/**
	 * Enable native-only mode (skip JDWP breakpoint registration).
	 */
	public static void setNativeOnlyMode(boolean enabled) {
		nativeOnlyMode = enabled;
		Log.info("Native-only mode: " + enabled);
	}

	/**
	 * Check if native-only mode is enabled.
	 */
	public static boolean isNativeOnlyMode() {
		return nativeOnlyMode;
	}

	/**
	 * Set the callback for native suspend events (breakpoints).
	 * LuceeVm should register this to receive notifications and send DAP stopped events.
	 */
	public static void setOnNativeSuspendCallback(BiConsumer<Long, String> callback) {
		onNativeSuspendCallback = callback;
	}

	/**
	 * Set the callback for native step events.
	 * LuceeVm should register this to receive notifications and send DAP step events.
	 */
	public static void setOnNativeStepCallback(Consumer<Long> callback) {
		onNativeStepCallback = callback;
	}

	/**
	 * Add a breakpoint at the given file and line.
	 */
	public static void addBreakpoint(String file, int line) {
		addBreakpoint(file, line, null);
	}

	/**
	 * Add a breakpoint at the given file and line with optional condition.
	 * @param condition CFML expression to evaluate, or null for unconditional breakpoint
	 */
	public static void addBreakpoint(String file, int line, String condition) {
		String key = makeKey(file, line);
		breakpoints.put(key, Boolean.TRUE);
		if (condition != null && !condition.isEmpty()) {
			breakpointConditions.put(key, condition);
			Log.info("Added native breakpoint: " + key + " condition=" + condition);
		} else {
			breakpointConditions.remove(key); // ensure no stale condition
			Log.info("Added native breakpoint: " + key);
		}
	}

	/**
	 * Remove a breakpoint at the given file and line.
	 */
	public static void removeBreakpoint(String file, int line) {
		String key = makeKey(file, line);
		breakpoints.remove(key);
		breakpointConditions.remove(key);
		Log.info("Removed native breakpoint: " + key);
	}

	/**
	 * Clear all breakpoints for a given file.
	 */
	public static void clearBreakpointsForFile(String file) {
		String prefix = Config.canonicalizeFileName(file) + ":";
		breakpoints.keySet().removeIf(key -> key.startsWith(prefix));
		breakpointConditions.keySet().removeIf(key -> key.startsWith(prefix));
		Log.info("Cleared native breakpoints for: " + file);
	}

	/**
	 * Clear all breakpoints.
	 */
	public static void clearAllBreakpoints() {
		breakpoints.clear();
		breakpointConditions.clear();
		Log.info("Cleared all native breakpoints");
	}

	/**
	 * Get breakpoint count (for debugging).
	 */
	public static int getBreakpointCount() {
		return breakpoints.size();
	}

	/**
	 * Check if a thread is natively suspended.
	 */
	public static boolean isNativelySuspended(long javaThreadId) {
		return nativelySuspendedThreads.containsKey(javaThreadId);
	}

	/**
	 * Get all suspended thread IDs.
	 * Used by NativeLuceeVm to include suspended threads in thread listing.
	 */
	public static java.util.Set<Long> getSuspendedThreadIds() {
		return new java.util.HashSet<>(nativelySuspendedThreads.keySet());
	}

	/**
	 * Get any PageContext from the suspended threads map.
	 * Used to bootstrap access to CFMLFactory for thread listing.
	 * @return a PageContext if any thread is suspended, null otherwise
	 */
	public static PageContext getAnyPageContext() {
		for (WeakReference<PageContext> ref : nativelySuspendedThreads.values()) {
			PageContext pc = ref.get();
			if (pc != null) {
				return pc;
			}
		}
		return null;
	}

	/**
	 * Get PageContext for a specific suspended thread.
	 * Used by NativeLuceeVm to get stack frames.
	 * @param javaThreadId The Java thread ID
	 * @return the PageContext if found and still valid, null otherwise
	 */
	public static PageContext getPageContext(long javaThreadId) {
		WeakReference<PageContext> ref = nativelySuspendedThreads.get(javaThreadId);
		if (ref != null) {
			return ref.get();
		}
		return null;
	}

	/**
	 * Get suspend location for a specific thread.
	 * Used to create synthetic frame for top-level code.
	 * @param javaThreadId The Java thread ID
	 * @return the SuspendLocation if thread is suspended, null otherwise
	 */
	public static SuspendLocation getSuspendLocation(long javaThreadId) {
		return suspendLocations.get(javaThreadId);
	}

	/**
	 * Resume a natively suspended thread by calling debuggerResume() on its PageContext.
	 * Uses reflection since debuggerResume() is a Lucee7+ method not in the loader interface.
	 * @return true if the thread was found and resumed, false otherwise
	 */
	public static boolean resumeNativeThread(long javaThreadId) {
		WeakReference<PageContext> pcRef = nativelySuspendedThreads.remove(javaThreadId);
		if (pcRef == null) {
			return false;
		}
		PageContext pc = pcRef.get();
		if (pc == null) {
			return false;
		}
		Log.info("Resuming native thread: " + javaThreadId);
		try {
			// Call debuggerResume() via reflection (Lucee7+ method)
			java.lang.reflect.Method resumeMethod = pc.getClass().getMethod("debuggerResume");
			resumeMethod.invoke(pc);
			return true;
		} catch (NoSuchMethodException e) {
			Log.error("debuggerResume() not available (pre-Lucee7?)");
			return false;
		} catch (Exception e) {
			Log.error("Error calling debuggerResume()", e);
			return false;
		}
	}

	/**
	 * Resume all natively suspended threads.
	 */
	public static void resumeAllNativeThreads() {
		for (Long threadId : nativelySuspendedThreads.keySet()) {
			resumeNativeThread(threadId);
		}
	}

	// ========== Stepping methods ==========

	/**
	 * Start stepping for a thread.
	 * @param threadId The Java thread ID
	 * @param mode The step mode (STEP_INTO, STEP_OVER, STEP_OUT)
	 * @param currentDepth The current stack depth when stepping started
	 */
	public static void startStepping(long threadId, StepMode mode, int currentDepth) {
		steppingThreads.put(threadId, new StepState(mode, currentDepth));
		Log.info("Start stepping: thread=" + threadId + " mode=" + mode + " depth=" + currentDepth);
	}

	/**
	 * Stop stepping for a thread.
	 */
	public static void stopStepping(long threadId) {
		steppingThreads.remove(threadId);
	}

	/**
	 * Get the current stack depth for a PageContext.
	 * Uses reflection to get debugger frames.
	 */
	public static int getStackDepth(PageContext pc) {
		try {
			java.lang.reflect.Method getFrames = pc.getClass().getMethod("getDebuggerFrames");
			Object[] frames = (Object[]) getFrames.invoke(pc);
			return frames != null ? frames.length : 0;
		} catch (Exception e) {
			// Log error - silent failure could cause incorrect step behavior
			Log.error("Error getting stack depth: " + e.getMessage());
			return 0;
		}
	}

	// ========== DebuggerListener interface methods ==========

	/**
	 * Called by Lucee when a thread is about to suspend.
	 * This is invoked on the suspending thread's stack, before it blocks.
	 */
	public static void onSuspend(PageContext pc, String file, int line, String label) {
		long threadId = Thread.currentThread().getId();
		Log.info("Native suspend: thread=" + threadId + " file=" + file + " line=" + line + " label=" + label);

		// Check if we were stepping BEFORE clearing state
		StepState stepState = steppingThreads.remove(threadId);
		boolean wasStepping = (stepState != null);

		// Check if we hit a breakpoint (breakpoint wins over step)
		boolean hitBreakpoint = breakpoints.containsKey(makeKey(file, line));

		// Check if there's a pending exception for this thread (from onException)
		Throwable pendingException = pendingExceptions.remove(threadId);

		// Track the suspended thread so we can resume it later
		// We store PageContext (not PageContextImpl) to avoid class loading cycles
		nativelySuspendedThreads.put(threadId, new WeakReference<>(pc));

		// Store suspend location for stack trace (needed when no native DebuggerFrames exist)
		// Include the exception if we're suspending due to one
		suspendLocations.put(threadId, new SuspendLocation(file, line, label, pendingException));

		// Fire appropriate callback - breakpoint takes precedence over step
		if (hitBreakpoint) {
			// Stopped at breakpoint (no label for line breakpoints)
			BiConsumer<Long, String> callback = onNativeSuspendCallback;
			if (callback != null) {
				callback.accept(threadId, null);
			}
		} else if (wasStepping) {
			// Stopped due to stepping
			Consumer<Long> callback = onNativeStepCallback;
			if (callback != null) {
				callback.accept(threadId);
			}
		} else {
			// Programmatic breakpoint() call or other suspend - pass the label
			BiConsumer<Long, String> callback = onNativeSuspendCallback;
			if (callback != null) {
				callback.accept(threadId, label);
			}
		}
	}

	/**
	 * Called by Lucee when a thread resumes after suspension.
	 */
	public static void onResume(PageContext pc) {
		long threadId = Thread.currentThread().getId();
		Log.info("Native resume: thread=" + threadId);

		// Remove from suspended threads map and location
		nativelySuspendedThreads.remove(threadId);
		suspendLocations.remove(threadId);
	}

	/**
	 * Check if a DAP client is connected and ready to handle breakpoints.
	 * Uses explicit flag set when DAP client connects, not just callback registration.
	 */
	public static boolean isDapClientConnected() {
		return dapClientConnected;
	}

	/**
	 * Set the DAP client connected state.
	 * Called by DapServer when client connects/disconnects.
	 */
	public static void setDapClientConnected(boolean connected) {
		dapClientConnected = connected;
		Log.info("DAP client connected: " + connected);
	}

	/**
	 * Set whether to break on uncaught exceptions.
	 * Called from DapServer when handling setExceptionBreakpoints request.
	 */
	public static void setBreakOnUncaughtExceptions(boolean enabled) {
		breakOnUncaughtExceptions = enabled;
		Log.info("Break on uncaught exceptions: " + enabled);
	}

	/**
	 * Check if we should break on uncaught exceptions.
	 */
	public static boolean shouldBreakOnUncaughtExceptions() {
		return breakOnUncaughtExceptions && dapClientConnected;
	}

	/**
	 * Called by Lucee when an exception is about to be handled.
	 * Returns true if we should suspend to let the debugger inspect.
	 *
	 * @param pc The PageContext
	 * @param exception The exception
	 * @param caught true if caught by try/catch, false if uncaught
	 * @return true to suspend execution
	 */
	public static boolean onException(PageContext pc, Throwable exception, boolean caught) {
		Log.info("onException called: caught=" + caught + ", exception=" + exception.getClass().getName() + ", breakOnUncaught=" + breakOnUncaughtExceptions + ", dapConnected=" + dapClientConnected);
		// Only handle uncaught exceptions for now
		if (caught) {
			return false;
		}
		boolean shouldSuspend = shouldBreakOnUncaughtExceptions();
		if (shouldSuspend) {
			// Store exception for this thread - will be consumed in onSuspend
			long threadId = Thread.currentThread().getId();
			pendingExceptions.put(threadId, exception);
		}
		Log.info("onException returning: " + shouldSuspend);
		return shouldSuspend;
	}

	/**
	 * Called by Lucee's DebuggerExecutionLog.start() on every line.
	 * Checks breakpoints AND stepping state.
	 * Must be fast - this is on the hot path.
	 */
	public static boolean shouldSuspend(PageContext pc, String file, int line) {
		// Early exit if no DAP client connected - nothing to notify
		if (!dapClientConnected) {
			return false;
		}

		// Check breakpoints first (most common case)
		String key = makeKey(file, line);
		if (breakpoints.containsKey(key)) {
			// Check if there's a condition
			String condition = breakpointConditions.get(key);
			if (condition != null) {
				// Evaluate condition - only suspend if true
				return evaluateCondition(pc, condition);
			}
			return true;
		}

		// Check stepping state
		long threadId = Thread.currentThread().getId();
		StepState stepState = steppingThreads.get(threadId);
		if (stepState == null) {
			return false;
		}

		int currentDepth = getStackDepth(pc);

		switch (stepState.mode) {
			case STEP_INTO:
				// Always stop on next line
				return true;

			case STEP_OVER:
				// Stop when at same or shallower depth
				return currentDepth <= stepState.startDepth;

			case STEP_OUT:
				// Stop when shallower than start depth
				return currentDepth < stepState.startDepth;

			default:
				return false;
		}
	}

	/**
	 * Evaluate a CFML condition expression and return its boolean result.
	 * Returns false if evaluation fails (exception, timeout, etc.).
	 */
	private static boolean evaluateCondition(PageContext pc, String condition) {
		try {
			// Use Evaluate.call() directly on PageContext - same approach as DebugManager
			Object result = lucee.runtime.functions.dynamicEvaluation.Evaluate.call(
				pc,
				new String[]{ condition }
			);
			return lucee.runtime.op.Caster.toBoolean(result);
		} catch (Exception e) {
			// Condition evaluation failed - don't suspend
			// Log but don't spam - conditions may intentionally reference undefined vars
			Log.debug("Condition evaluation failed: " + e.getMessage());
			return false;
		}
	}

	/**
	 * Check if a breakpoint exists at the given file and line.
	 */
	public static boolean hasBreakpoint(String file, int line) {
		String key = makeKey(file, line);
		return breakpoints.containsKey(key);
	}

	private static String makeKey(String file, int line) {
		return Config.canonicalizeFileName(file) + ":" + line;
	}
}
