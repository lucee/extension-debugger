package luceedebug.coreinject;

import java.lang.ref.WeakReference;
import java.util.concurrent.ConcurrentHashMap;
import java.util.function.BiConsumer;
import java.util.function.Consumer;

import lucee.runtime.PageContext;
import luceedebug.Config;

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
		System.out.println("[luceedebug] Native-only mode: " + enabled);
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
			System.out.println("[luceedebug] Added native breakpoint: " + key + " condition=" + condition);
		} else {
			breakpointConditions.remove(key); // ensure no stale condition
			System.out.println("[luceedebug] Added native breakpoint: " + key);
		}
	}

	/**
	 * Remove a breakpoint at the given file and line.
	 */
	public static void removeBreakpoint(String file, int line) {
		String key = makeKey(file, line);
		breakpoints.remove(key);
		breakpointConditions.remove(key);
		System.out.println("[luceedebug] Removed native breakpoint: " + key);
	}

	/**
	 * Clear all breakpoints for a given file.
	 */
	public static void clearBreakpointsForFile(String file) {
		String prefix = Config.canonicalizeFileName(file) + ":";
		breakpoints.keySet().removeIf(key -> key.startsWith(prefix));
		breakpointConditions.keySet().removeIf(key -> key.startsWith(prefix));
		System.out.println("[luceedebug] Cleared native breakpoints for: " + file);
	}

	/**
	 * Clear all breakpoints.
	 */
	public static void clearAllBreakpoints() {
		breakpoints.clear();
		breakpointConditions.clear();
		System.out.println("[luceedebug] Cleared all native breakpoints");
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
		System.out.println("[luceedebug] Resuming native thread: " + javaThreadId);
		try {
			// Call debuggerResume() via reflection (Lucee7+ method)
			java.lang.reflect.Method resumeMethod = pc.getClass().getMethod("debuggerResume");
			resumeMethod.invoke(pc);
			return true;
		} catch (NoSuchMethodException e) {
			System.out.println("[luceedebug] debuggerResume() not available (pre-Lucee7?)");
			return false;
		} catch (Exception e) {
			System.out.println("[luceedebug] Error calling debuggerResume(): " + e.getMessage());
			e.printStackTrace();
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
		System.out.println("[luceedebug] Start stepping: thread=" + threadId + " mode=" + mode + " depth=" + currentDepth);
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
			System.out.println("[luceedebug] Error getting stack depth: " + e.getMessage());
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
		System.out.println("[luceedebug] Native suspend: thread=" + threadId + " file=" + file + " line=" + line + " label=" + label);

		// Check if we were stepping BEFORE clearing state
		StepState stepState = steppingThreads.remove(threadId);
		boolean wasStepping = (stepState != null);

		// Check if we hit a breakpoint (breakpoint wins over step)
		boolean hitBreakpoint = breakpoints.containsKey(makeKey(file, line));

		// Track the suspended thread so we can resume it later
		// We store PageContext (not PageContextImpl) to avoid class loading cycles
		nativelySuspendedThreads.put(threadId, new WeakReference<>(pc));

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
		System.out.println("[luceedebug] Native resume: thread=" + threadId);

		// Remove from suspended threads map
		nativelySuspendedThreads.remove(threadId);
	}

	/**
	 * Called by Lucee's DebuggerExecutionLog.start() on every line.
	 * Checks breakpoints AND stepping state.
	 * Must be fast - this is on the hot path.
	 */
	public static boolean shouldSuspend(PageContext pc, String file, int line) {
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
			System.out.println("[luceedebug] Condition evaluation failed: " + e.getMessage());
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
