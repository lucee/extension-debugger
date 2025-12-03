# CFML DAP Client for Debugger Testing

## Goal

Create a pure CFML DAP client to test luceedebug without VS Code involvement. This enables automated testing and can be bundled with the extension for users.

## Architecture

```
Instance A (test runner)          Instance B (debuggee)
─────────────────────────         ────────────────────────
DapClient.cfc                     luceedebug + Lucee7
test-*.cfm                        target scripts
  │                                 │
  │ DAP socket ──────────────────>  │ port 10000
  │ HTTP trigger ─────────────────> │ port 8888
```

**Critical**: Test runner must NOT run with debugger enabled to avoid deadlock.

## Files to Create

### 1. `profiling/DapClient.cfc`

DAP protocol client with:

- **Connection**: TCP socket via `java.net.Socket`
- **Framing**: `Content-Length: N\r\n\r\n{json}`
- **Sequence tracking**: Auto-increment request seq
- **Response/event handling**: Separate queues for responses vs events

Methods:

- `connect( host, port )` / `disconnect()`
- `initialize()` - DAP initialize handshake
- `setBreakpoints( path, lines[] )` - Set breakpoints for file
- `configurationDone()` - Signal ready to run
- `continue( threadId )` / `continueAll()`
- `stackTrace( threadId )` - Get stack frames
- `scopes( frameId )` - Get variable scopes
- `variables( variablesReference )` - Get variables
- `threads()` - List threads
- `waitForEvent( type, timeoutMs )` - Wait for specific event (stopped, thread, etc.)
- `stepOver( threadId )` / `stepIn( threadId )` / `stepOut( threadId )`

### 2. `profiling/test-dap-breakpoint.cfm`

Test native breakpoint flow:

1. Connect to debuggee DAP port
2. Set breakpoint on target file
3. HTTP request to trigger target (async thread)
4. Wait for "stopped" event
5. Verify stack trace shows correct file/line
6. Continue and verify request completes

### 3. `profiling/dap-target.cfm`

Simple target script in debuggee webroot:

```cfml
function testFunc( name ) {
    var greeting = "Hello, #name#!";  // <- breakpoint here
    return greeting;
}
result = testFunc( "World" );
```

## DAP Protocol Notes

Message format:

```
Content-Length: 119\r\n
\r\n
{"seq":1,"type":"request","command":"initialize","arguments":{"clientID":"cfml-test","adapterID":"luceedebug"}}
```

Key request/response pairs:

- `initialize` -> capabilities
- `setBreakpoints` -> breakpoint[] with verified flag
- `configurationDone` -> empty
- `continue` -> empty
- `stackTrace` -> stackFrames[]
- `threads` -> threads[]

Key events:

- `stopped` - thread hit breakpoint (body.threadId, body.reason)
- `thread` - thread started/exited

## Implementation Order

1. DapClient.cfc - core protocol
2. Basic test - connect, initialize, disconnect
3. Breakpoint test - full flow with target script
4. Step test - stepOver/stepIn/stepOut (once Phase 2 native stepping is done)
