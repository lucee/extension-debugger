package luceedebug.coreinject;

import java.util.ArrayList;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.function.BiConsumer;
import java.util.function.Consumer;

import luceedebug.*;
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

	private Consumer<Long> stepEventCallback = null;
	private BiConsumer<Long, DapBreakpointID> breakpointEventCallback = null;
	private BiConsumer<Long, String> nativeBreakpointEventCallback = null;
	private Consumer<BreakpointsChangedEvent> breakpointsChangedCallback = null;

	private AtomicInteger breakpointID = new AtomicInteger();

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

	@Override
	public ThreadInfo[] getThreadListing() {
		var result = new ArrayList<ThreadInfo>();

		// Get active PageContexts from Lucee's CFMLFactory
		// We need a PageContext to get the factory - try ThreadLocalPageContext or suspended threads
		lucee.runtime.PageContext anyPc = lucee.runtime.engine.ThreadLocalPageContext.get();

		// If not on a request thread, try to get from suspended threads
		if (anyPc == null) {
			anyPc = NativeDebuggerListener.getAnyPageContext();
		}

		if (anyPc != null) {
			try {
				// Get the CFMLFactory from the PageContext
				Object factory = anyPc.getCFMLFactory();

				// Call getActivePageContexts() via reflection (it's in CFMLFactoryImpl, not loader)
				java.lang.reflect.Method getActiveMethod = factory.getClass().getMethod("getActivePageContexts");
				@SuppressWarnings("unchecked")
				java.util.Map<Integer, ?> activeContexts = (java.util.Map<Integer, ?>) getActiveMethod.invoke(factory);

				// Each PageContext has a getThread() method
				for (Object pc : activeContexts.values()) {
					try {
						java.lang.reflect.Method getThreadMethod = pc.getClass().getMethod("getThread");
						Thread thread = (Thread) getThreadMethod.invoke(pc);
						if (thread != null) {
							result.add(new ThreadInfo(thread.getId(), thread.getName()));
						}
					} catch (Exception e) {
						// Skip this context if we can't get its thread
					}
				}
			} catch (Exception e) {
				System.out.println("[luceedebug] Error getting active page contexts: " + e.getMessage());
			}
		}

		return result.toArray(new ThreadInfo[0]);
	}

	@Override
	public IDebugFrame[] getStackTrace(long threadID) {
		// Get the thread and use DebugManager to get CF stack
		Thread thread = findThreadById(threadID);
		if (thread == null) {
			return new IDebugFrame[0];
		}
		return GlobalIDebugManagerHolder.debugManager.getCfStack(thread);
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
		return GlobalIDebugManagerHolder.debugManager.getScopesForFrame(frameID);
	}

	@Override
	public IDebugEntity[] getVariables(long ID) {
		return GlobalIDebugManagerHolder.debugManager.getVariables(ID, null);
	}

	@Override
	public IDebugEntity[] getNamedVariables(long ID) {
		return GlobalIDebugManagerHolder.debugManager.getVariables(ID, IDebugEntity.DebugEntityType.NAMED);
	}

	@Override
	public IDebugEntity[] getIndexedVariables(long ID) {
		return GlobalIDebugManagerHolder.debugManager.getVariables(ID, IDebugEntity.DebugEntityType.INDEXED);
	}

	// ========== Breakpoint operations ==========

	@Override
	public IBreakpoint[] bindBreakpoints(RawIdePath idePath, CanonicalServerAbsPath serverPath, int[] lines, String[] exprs) {
		// Clear existing native breakpoints for this file
		NativeDebuggerListener.clearBreakpointsForFile(serverPath.get());

		// Add native breakpoints with optional conditions
		IBreakpoint[] result = new Breakpoint[lines.length];
		for (int i = 0; i < lines.length; i++) {
			String condition = (exprs != null && i < exprs.length) ? exprs[i] : null;
			NativeDebuggerListener.addBreakpoint(serverPath.get(), lines[i], condition);
			// Native breakpoints are always "bound" - no class loading dependency
			result[i] = Breakpoint.Bound(lines[i], nextDapBreakpointID());
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
		return GlobalIDebugManagerHolder.debugManager.evaluate((Long)(long)frameID, expr);
	}
}
