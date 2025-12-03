# Native Lucee Debugging Plan

Goal: Make debugging Lucee as easy as possible - install extension, connect VS Code, go.

## Current State (done)

- `DEBUGGER_ENABLED` env var/system property enables debug mode
- Native `DebuggerFrame` stack in PageContextImpl (push/pop on UDF calls)
- `ExecutionLog.start(pos, line, id)` passes line numbers from compiler
- `DebuggerExecutionLog` updates frame line numbers
- luceedebug can read native frames via reflection fallback (`NativeDebugFrame.java`)
- **Tested working**: luceedebug agent + Lucee7 with native frames (2025-12-03)
  - Agent starts, connects to JDWP, DAP server listens on port 10000
  - Native frames show correct function names, file paths, local variables, arguments
  - Test script: `profiling/test-native-frames-with-agent.bat`

## Phase 1: Native Breakpoints ✅ DONE (Lucee core parts)

### Lucee Core Changes - IMPLEMENTED

1. ✅ **DebuggerListener interface** (`lucee.runtime.debug.DebuggerListener`)
   ```java
   public interface DebuggerListener {
       void onSuspend(PageContext pc, String file, int line, String label);
       void onResume(PageContext pc);
       boolean hasBreakpoint(String file, int line);
   }
   ```

2. ✅ **DebuggerRegistry** (`lucee.runtime.debug.DebuggerRegistry`)
   - Static singleton for listener registration
   - `setListener(listener)` / `getListener()` / `hasListener()`
   - luceedebug accesses via reflection

3. ✅ **Breakpoint Check in DebuggerExecutionLog.start()**
   ```java
   public void start(int pos, int line, String id) {
       DebuggerFrame frame = pci.getTopmostDebuggerFrame();
       if (frame != null) {
           frame.setLine(line);
           DebuggerListener listener = DebuggerRegistry.getListener();
           if (listener != null && listener.hasBreakpoint(frame.getFile(), line)) {
               pci.debuggerSuspend(null);
           }
       }
   }
   ```

4. ✅ **Thread Suspension with callbacks** in PageContextImpl
   - `debuggerSuspend(label)` calls `listener.onSuspend()` before blocking
   - Calls `listener.onResume()` after unblocking
   - Tracks `debuggerTotalSuspendedNanos` for timeout adjustment

5. ⏳ **Timeout Pausing** - `debuggerTotalSuspendedNanos` tracked but not yet wired into timeout calc

### luceedebug Changes - IMPLEMENTED

1. ✅ **NativeDebuggerListener** class (`luceedebug.coreinject.NativeDebuggerListener`)
   - Breakpoint map: `ConcurrentHashMap<String, Boolean>` for "file:line" -> true
   - Tracks natively suspended threads: `ConcurrentHashMap<Long, WeakReference<PageContextImpl>>`
   - `onSuspend()` / `onResume()` / `hasBreakpoint()` interface methods
   - `resumeNativeThread()` calls `debuggerResume()` via reflection

2. ✅ **Register via reflection** in `LuceeTransformer.registerNativeDebuggerListener()`
   - Creates dynamic proxy implementing `DebuggerListener`
   - Registers with `DebuggerRegistry.setListener()`
   - Gracefully falls back if DebuggerRegistry not available (pre-Lucee7)

3. ✅ **DAP stopped event** from `onSuspend` callback
   - `LuceeVm.registerNativeBreakpointEventCallback()` receives Java thread ID
   - `DapServer` sends `StoppedEventArguments` to VS Code

4. ✅ **Continue support** for native threads
   - `LuceeVm.continue_(long)` tries native resume first, falls back to JDWP
   - `continueAll()` resumes both native and JDWP suspended threads

5. ✅ **Wire breakpoints to NativeDebuggerListener**
   - `bindBreakpoints()` clears and adds native breakpoints for file
   - `clearAllBreakpoints()` clears native breakpoints

6. ✅ **Native-only mode flag** (skip JDWP breakpoint registration)
   - `NativeDebuggerListener.setNativeOnlyMode(true)` enables native-only mode
   - When enabled, `bindBreakpoints()` skips JDWP registration, returns all breakpoints as "bound"
   - `clearAllBreakpoints()` skips JDWP operations in native-only mode
   - NOTE: This is for hybrid agent mode. True extension mode needs `NativeLuceeVm` (see below)

7. ✅ **NativeLuceeVm** - ILuceeVm implementation without JDWP (stubbed)
   - For true extension deployment (no agent, no JDWP, no bytecode instrumentation)
   - Implements `ILuceeVm` interface using only native Lucee7 debugging APIs
   - No `VirtualMachine` dependency
   - Refactored `ILuceeVm` to remove JDWP types (`ThreadReference` -> `ThreadInfo`, `JdwpThreadID` -> `Long`)
   - ✅ Thread listing via `CFMLFactoryImpl.getActivePageContexts()` (reflection)
   - Stack frames via native `DebuggerFrame` stack (working)
   - Variables via `CfValueDebuggerBridge` (working)
   - ⏳ Native stepping - needs Phase 2 implementation

## Phase 2: Stepping

### Step Into
- Set flag `stepMode = STEP_INTO`
- Next `start()` call suspends

### Step Over
- Record current frame depth
- Set flag `stepMode = STEP_OVER, stepDepth = currentDepth`
- Suspend when `start()` called at same or lower depth

### Step Out
- Record current frame depth
- Set flag `stepMode = STEP_OUT, stepDepth = currentDepth`
- Suspend when frame depth < stepDepth

```java
// In DebuggerExecutionLog.start()
if (stepMode == STEP_INTO) {
    suspend();
} else if (stepMode == STEP_OVER && currentDepth <= stepDepth) {
    suspend();
} else if (stepMode == STEP_OUT && currentDepth < stepDepth) {
    suspend();
}
```

## Phase 3: Conditional Breakpoints & Watches

- Breakpoint conditions: evaluate CFML expression, break if truthy
- Watch expressions: evaluate on suspend, show in VS Code
- Both use existing `Evaluate.call()` infrastructure

## Phase 4: Programmatic Breakpoints ✅ DONE

BIF `breakpoint()` - like JavaScript's `debugger;` statement.

```cfml
// Simple - pause here
breakpoint();

// Conditional - only pause when condition is true
breakpoint( user.isAdmin() );

// Labeled - shows in debugger UI
breakpoint( label="after auth check" );
```

Implementation:
```java
public class Breakpoint extends BIF {
    public static Object call(PageContext pc) {
        return call(pc, true, null);
    }
    public static Object call(PageContext pc, boolean condition, String label) {
        if (condition && PageContextImpl.DEBUGGER_ENABLED) {
            ((PageContextImpl) pc).debuggerSuspend(label);
        }
        return null;
    }
}
```

Benefits:
- Conditional breakpoints without IDE config
- Debug specific code paths
- Zero cost when DEBUGGER_ENABLED=false
- Works in production - flip flag, attach, hit code path

## Open Questions

1. ✅ **Loader interface changes** - RESOLVED: No loader changes needed. DebuggerListener/Registry in core, accessed via reflection.
2. **Extension loading order** - debugger extension needs to init early
3. ✅ **Multiple debuggers** - RESOLVED: Single listener only. Keep it simple.
4. **Remote debugging** - DAP over network vs localhost only?
5. **Performance** - hash lookup per line acceptable? Profile it. (hasBreakpoint called on every line)

## Migration Path

1. Ship Lucee 7.1 with native debug support
2. Ship luceedebug 2.0 as extension (no agent required)
3. Keep agent mode working for older Lucee versions
4. Deprecate agent mode eventually
