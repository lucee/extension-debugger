# Native Debugging Testing Plan

Testing native stepping for Lucee7+ debugger without JDWP.

## Test Infrastructure

### Option 1: Local Tomcat (Recommended for interactive testing)

Use the existing Lucee7 Tomcat setup at `D:\lucee7\tomcat`:

```cmd
rem Start Tomcat with luceedebug agent
cd D:\lucee7\tomcat\bin
set LUCEE_DEBUGGER_ENABLED=true
set lucee_logging_force_level=trace
set lucee_logging_force_appender=console
startup.bat
```

Then connect VS Code debugger to port 10000 and test stepping manually.

### Option 2: Script-runner (For automated headless tests)

Use script-runner for headless CFML execution:

```cmd
ant -buildfile "D:\work\script-runner" ^
    -DluceeJar="D:\work\lucee7\loader\target\lucee-7.1.0.7-ALPHA.jar" ^
    -Dwebroot="D:\work\lucee-extensions\luceedebug\profiling" ^
    -Dexecute="test-debugger-frames.cfm" ^
    -Djdwp="true" ^
    -DjdwpPort="9999" ^
    -DjavaAgent="D:\work\lucee-extensions\luceedebug\luceedebug\build\libs\luceedebug-2.0.15.jar" ^
    -DjavaAgentArgs="jdwpHost=localhost,jdwpPort=9999,debugHost=0.0.0.0,debugPort=10000,jarPath=..."
```

**Limitation**: Script-runner is headless (no HTTP server), so DAP tests that require triggering breakpoints via HTTP won't work.

### Option 3: Two-instance DAP testing

For full DAP protocol testing (breakpoints, stepping via DAP commands):

1. **Instance A (debuggee)**: Lucee with luceedebug, HTTP server on 8888, DAP on 10000
2. **Instance B (test runner)**: Lucee WITHOUT debugger, runs test script

The test script (Instance B) connects to DAP (10000), sets breakpoints, triggers HTTP requests to Instance A (8888), and verifies stepping behavior.

## Test Files

| File | Purpose |
|------|---------|
| `test-debugger-frames.cfm` | Tests native `getDebuggerFrames()` API |
| `test-breakpoint-bif.cfm` | Tests `breakpoint()` BIF |
| `dap-target.cfm` | Simple target for DAP breakpoint tests |
| `dap-step-target.cfm` | Target with nested functions for stepping tests |
| `test-dap-breakpoint.cfm` | DAP breakpoint test (needs 2 instances) |
| `test-dap-stepping.cfm` | DAP stepping test (needs 2 instances) |
| `DapClient.cfc` | CFML DAP protocol client |

## Test Scenarios

### 1. Native Frame API (no DAP)

**Script**: `test-debugger-frames.cfm`
**Tests**:

- [x] `DEBUGGER_ENABLED` flag detection
- [x] `getDebuggerFrames()` returns correct frame count
- [x] Frame contains function name, file path, locals, arguments
- [x] Nested function calls show correct stack

### 2. Breakpoint BIF (no DAP)

**Script**: `test-breakpoint-bif.cfm`
**Tests**:

- [ ] `breakpoint()` suspends execution when debugger enabled
- [ ] `breakpoint(false)` does not suspend
- [ ] `breakpoint(true, "label")` shows label in debugger
- [ ] `breakpoint()` is no-op when debugger disabled

### 3. DAP Breakpoints

**Script**: `test-dap-breakpoint.cfm`
**Requires**: Two Lucee instances
**Tests**:

- [ ] DAP connection and initialization
- [ ] Set breakpoints via `setBreakpoints` command
- [ ] Breakpoint hit sends `stopped` event
- [ ] Stack trace shows correct file/line
- [ ] Variables visible in scopes
- [ ] Continue resumes execution

### 4. DAP Stepping

**Script**: `test-dap-stepping.cfm`
**Requires**: Two Lucee instances
**Tests**:

- [ ] **Step Over** (`next`): Executes function call, stops on next line
- [ ] **Step In** (`stepIn`): Enters function, stops on first line
- [ ] **Step Out** (`stepOut`): Runs to function return, stops in caller
- [ ] Step + breakpoint: Stepping stops at breakpoints too
- [ ] Nested stepping: Step in/out through multiple call levels

## Manual Testing with VS Code

1. Start Lucee7 Tomcat with luceedebug agent
2. Open VS Code, create launch.json:
   ```json
   {
     "type": "cfml",
     "request": "attach",
     "name": "Attach to Lucee",
     "hostName": "localhost",
     "port": 10000
   }
   ```
3. Set breakpoint in a .cfm file
4. Trigger the page via browser
5. Test stepping buttons: Step Over (F10), Step In (F11), Step Out (Shift+F11)

## Expected Stepping Behavior

Given this code:
```cfml
function inner() {
    var x = 1;    // line 2
    return x;     // line 3
}

function outer() {
    var a = 0;           // line 7
    var b = inner();     // line 8 - step in goes to line 2
    var c = b + 1;       // line 9 - step over from line 8 goes here
    return c;            // line 10
}

result = outer();        // line 13 - breakpoint here
done = true;             // line 14
```

| Action | From | To | Stack Depth Change |
|--------|------|----|--------------------|
| Step Over | line 13 | line 14 | same |
| Step In | line 13 | line 7 | +1 |
| Step In | line 8 | line 2 | +1 |
| Step Over | line 8 | line 9 | same |
| Step Out | line 2 | line 9 | -1 |
| Step Out | line 7 | line 14 | -1 |

## Debugging Test Failures

### Enable trace logging

```cmd
set lucee_logging_force_level=trace
set lucee_logging_force_appender=console
```

### Check luceedebug output

Look for `[luceedebug]` prefixed messages:

- `Registered native debugger listener` - listener registered OK
- `Native-only mode: true` - using native breakpoints
- `Added native breakpoint: /path/file.cfm:10` - breakpoint set
- `Native suspend: thread=123 file=... line=10` - breakpoint hit
- `Start stepping: thread=123 mode=STEP_OVER depth=3` - stepping started
- `Resuming native thread: 123` - continue/step executed

### Common issues

1. **No suspend on breakpoint**: Check `LUCEE_DEBUGGER_ENABLED=true`
2. **DebuggerRegistry not found**: Lucee version too old (need 7.1+)
3. **Stepping doesn't stop**: Check `shouldSuspend()` logic
4. **Wrong line after step**: Check stack depth calculation
