<cfscript>
/**
 * DAP Stepping Test
 *
 * Tests stepIn, stepOver, stepOut functionality via the DAP protocol.
 *
 * IMPORTANT: This script must run on a DIFFERENT Lucee instance than the debuggee!
 * Otherwise, when the breakpoint hits, this test script will also be frozen.
 *
 * Setup:
 *   - Instance A (test runner): Runs this script, NO debugger
 *   - Instance B (debuggee): Runs with luceedebug agent on port 10000, HTTP on 8888
 *
 * Usage:
 *   Configure the variables below, then run this script.
 */

// ========== Configuration ==========
DAP_HOST = "localhost";
DAP_PORT = 10000;
DEBUGGEE_HTTP = "http://localhost:8888";
TARGET_FILE = "/app/profiling/dap-step-target.cfm";  // Path as seen by debuggee
BREAKPOINT_LINE = 20;  // Line with outerFunc call
// ===================================

systemOutput( "=== DAP Stepping Test ===", true );
systemOutput( "", true );

// Track test results
testResults = { passed: 0, failed: 0, errors: [] };

function assert( required boolean condition, required string message ) {
	if ( arguments.condition ) {
		testResults.passed++;
		systemOutput( "  PASS: #arguments.message#", true );
	} else {
		testResults.failed++;
		testResults.errors.append( arguments.message );
		systemOutput( "  FAIL: #arguments.message#", true );
	}
}

function assertLine( required numeric expected, required numeric actual, required string context ) {
	assert( arguments.actual == arguments.expected, "#arguments.context#: expected line #arguments.expected#, got #arguments.actual#" );
}

dap = new DapClient( debug = true );

try {
	// Connect to debugger
	systemOutput( "Connecting to DAP server at #DAP_HOST#:#DAP_PORT#...", true );
	dap.connect( DAP_HOST, DAP_PORT );
	systemOutput( "Connected!", true );

	// Initialize
	systemOutput( "", true );
	systemOutput( "Initializing DAP session...", true );
	initResponse = dap.initialize();
	systemOutput( "Initialized.", true );

	// Set breakpoint
	systemOutput( "", true );
	systemOutput( "Setting breakpoint at #TARGET_FILE#:#BREAKPOINT_LINE#...", true );
	bpResponse = dap.setBreakpoints( TARGET_FILE, [ BREAKPOINT_LINE ] );
	systemOutput( "Breakpoints set.", true );

	// Configuration done
	dap.configurationDone();
	systemOutput( "Ready!", true );

	// Trigger the target script via HTTP (in a separate thread so we don't block)
	systemOutput( "", true );
	systemOutput( "Triggering target script via HTTP...", true );

	httpResult = {};
	thread name="httpTrigger" httpResult=httpResult DEBUGGEE_HTTP=DEBUGGEE_HTTP {
		try {
			http url="#DEBUGGEE_HTTP#/profiling/dap-step-target.cfm" result="local.r" timeout=60;
			httpResult.status = local.r.statusCode;
			httpResult.content = local.r.fileContent;
		} catch ( any e ) {
			httpResult.error = e.message;
		}
	}

	// ========== Test 1: Initial breakpoint hit ==========
	systemOutput( "", true );
	systemOutput( "=== Test 1: Initial Breakpoint ===", true );

	stoppedEvent = dap.waitForEvent( "stopped", 15000 );
	threadId = stoppedEvent.body.threadId;
	systemOutput( "Thread ID: #threadId#", true );

	stackResponse = dap.stackTrace( threadId );
	frames = stackResponse.body.stackFrames ?: [];

	if ( frames.len() > 0 ) {
		assertLine( BREAKPOINT_LINE, frames[ 1 ].line, "Initial breakpoint" );
	} else {
		testResults.failed++;
		testResults.errors.append( "No stack frames at initial breakpoint" );
	}

	// ========== Test 2: Step Over ==========
	systemOutput( "", true );
	systemOutput( "=== Test 2: Step Over (should stay at line 21) ===", true );

	dap.stepOver( threadId );
	stoppedEvent = dap.waitForEvent( "stopped", 5000 );

	stackResponse = dap.stackTrace( threadId );
	frames = stackResponse.body.stackFrames ?: [];

	if ( frames.len() > 0 ) {
		assertLine( 21, frames[ 1 ].line, "Step over from line 20" );
	}

	// ========== Reset: Continue and hit breakpoint again ==========
	systemOutput( "", true );
	systemOutput( "=== Resetting: Continue to end, re-trigger ===", true );

	dap.continueThread( threadId );

	// Wait for HTTP to finish
	threadJoin( "httpTrigger", 5000 );
	systemOutput( "First run completed.", true );

	// Re-trigger for stepIn test
	httpResult = {};
	thread name="httpTrigger2" httpResult=httpResult DEBUGGEE_HTTP=DEBUGGEE_HTTP {
		try {
			http url="#DEBUGGEE_HTTP#/profiling/dap-step-target.cfm" result="local.r" timeout=60;
			httpResult.status = local.r.statusCode;
			httpResult.content = local.r.fileContent;
		} catch ( any e ) {
			httpResult.error = e.message;
		}
	}

	stoppedEvent = dap.waitForEvent( "stopped", 15000 );
	threadId = stoppedEvent.body.threadId;

	// ========== Test 3: Step Over (execute outerFunc, land on line 21) ==========
	systemOutput( "", true );
	systemOutput( "=== Test 3: Step Over outerFunc call ===", true );

	dap.stepOver( threadId );
	stoppedEvent = dap.waitForEvent( "stopped", 5000 );

	stackResponse = dap.stackTrace( threadId );
	frames = stackResponse.body.stackFrames ?: [];

	if ( frames.len() > 0 ) {
		assertLine( 21, frames[ 1 ].line, "Step over outerFunc" );
	}

	// ========== Test 4: Continue to end, re-trigger for stepIn ==========
	systemOutput( "", true );
	systemOutput( "=== Test 4: Step In test ===", true );

	dap.continueThread( threadId );
	threadJoin( "httpTrigger2", 5000 );

	// Re-trigger for stepIn test
	httpResult = {};
	thread name="httpTrigger3" httpResult=httpResult DEBUGGEE_HTTP=DEBUGGEE_HTTP {
		try {
			http url="#DEBUGGEE_HTTP#/profiling/dap-step-target.cfm" result="local.r" timeout=60;
			httpResult.status = local.r.statusCode;
			httpResult.content = local.r.fileContent;
		} catch ( any e ) {
			httpResult.error = e.message;
		}
	}

	stoppedEvent = dap.waitForEvent( "stopped", 15000 );
	threadId = stoppedEvent.body.threadId;

	// Step into outerFunc
	dap.stepIn( threadId );
	stoppedEvent = dap.waitForEvent( "stopped", 5000 );

	stackResponse = dap.stackTrace( threadId );
	frames = stackResponse.body.stackFrames ?: [];

	if ( frames.len() > 0 ) {
		// Should be inside outerFunc, line 12
		assertLine( 12, frames[ 1 ].line, "Step into outerFunc" );
	}

	// ========== Test 5: Step Out ==========
	systemOutput( "", true );
	systemOutput( "=== Test 5: Step Out ===", true );

	dap.stepOut( threadId );
	stoppedEvent = dap.waitForEvent( "stopped", 5000 );

	stackResponse = dap.stackTrace( threadId );
	frames = stackResponse.body.stackFrames ?: [];

	if ( frames.len() > 0 ) {
		// Should be back at line 21 (after outerFunc call)
		assertLine( 21, frames[ 1 ].line, "Step out of outerFunc" );
	}

	// Continue to complete
	dap.continueThread( threadId );
	threadJoin( "httpTrigger3", 5000 );

	// ========== Summary ==========
	systemOutput( "", true );
	systemOutput( "========================================", true );
	systemOutput( "TEST SUMMARY", true );
	systemOutput( "========================================", true );
	systemOutput( "Passed: #testResults.passed#", true );
	systemOutput( "Failed: #testResults.failed#", true );

	if ( testResults.errors.len() > 0 ) {
		systemOutput( "", true );
		systemOutput( "Failures:", true );
		for ( var err in testResults.errors ) {
			systemOutput( "  - #err#", true );
		}
	}

	if ( testResults.failed == 0 ) {
		systemOutput( "", true );
		systemOutput( "ALL TESTS PASSED!", true );
	}

} catch ( any e ) {
	systemOutput( "", true );
	systemOutput( "ERROR: #e.message#", true );
	systemOutput( e.stackTrace, true );
} finally {
	dap.disconnect();
}
</cfscript>
