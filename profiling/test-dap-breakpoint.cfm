<cfscript>
/**
 * DAP Breakpoint Test
 *
 * Tests that native breakpoints work via the DAP protocol.
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
TARGET_FILE = "/app/profiling/dap-target.cfm";  // Path as seen by debuggee
BREAKPOINT_LINE = 7;  // Line inside testFunc
// ===================================

systemOutput( "=== DAP Breakpoint Test ===" );
systemOutput( "" );

dap = new DapClient( debug = true );

try {
	// Connect to debugger
	systemOutput( "Connecting to DAP server at #DAP_HOST#:#DAP_PORT#..." );
	dap.connect( DAP_HOST, DAP_PORT );
	systemOutput( "Connected!" );

	// Initialize
	systemOutput( "" );
	systemOutput( "Initializing DAP session..." );
	initResponse = dap.initialize();
	systemOutput( "Initialized. Capabilities: #serializeJSON( initResponse.body ?: {} )#" );

	// Set breakpoint
	systemOutput( "" );
	systemOutput( "Setting breakpoint at #TARGET_FILE#:#BREAKPOINT_LINE#..." );
	bpResponse = dap.setBreakpoints( TARGET_FILE, [ BREAKPOINT_LINE ] );
	systemOutput( "Breakpoints: #serializeJSON( bpResponse.body ?: {} )#" );

	// Configuration done
	systemOutput( "" );
	systemOutput( "Sending configurationDone..." );
	dap.configurationDone();
	systemOutput( "Ready!" );

	// Trigger the target script via HTTP (in a separate thread so we don't block)
	systemOutput( "" );
	systemOutput( "Triggering target script via HTTP..." );

	httpResult = {};
	thread name="httpTrigger" httpResult=httpResult DEBUGGEE_HTTP=DEBUGGEE_HTTP {
		try {
			http url="#DEBUGGEE_HTTP#/profiling/dap-target.cfm" result="local.r" timeout=30;
			httpResult.status = local.r.statusCode;
			httpResult.content = local.r.fileContent;
		} catch ( any e ) {
			httpResult.error = e.message;
		}
	}

	// Wait for stopped event
	systemOutput( "Waiting for breakpoint to hit..." );
	stoppedEvent = dap.waitForEvent( "stopped", 10000 );
	systemOutput( "" );
	systemOutput( "=== BREAKPOINT HIT ===" );
	systemOutput( "Thread ID: #stoppedEvent.body.threadId#" );
	systemOutput( "Reason: #stoppedEvent.body.reason#" );

	// Get stack trace
	systemOutput( "" );
	systemOutput( "Getting stack trace..." );
	stackResponse = dap.stackTrace( stoppedEvent.body.threadId );
	frames = stackResponse.body.stackFrames ?: [];

	systemOutput( "Stack frames (#frames.len()#):" );
	for ( var i = 1; i <= min( frames.len(), 5 ); i++ ) {
		var frame = frames[ i ];
		systemOutput( "  [#i#] #frame.name# at #frame.source.path ?: 'unknown'#:#frame.line#" );
	}

	// Verify we stopped at the right place
	if ( frames.len() > 0 ) {
		var topFrame = frames[ 1 ];
		if ( topFrame.line == BREAKPOINT_LINE ) {
			systemOutput( "" );
			systemOutput( "SUCCESS: Stopped at expected line #BREAKPOINT_LINE#" );
		} else {
			systemOutput( "" );
			systemOutput( "WARNING: Expected line #BREAKPOINT_LINE#, got #topFrame.line#" );
		}

		// Get scopes and variables for top frame
		systemOutput( "" );
		systemOutput( "Getting scopes for frame #topFrame.id#..." );
		scopesResponse = dap.scopes( topFrame.id );
		scopes = scopesResponse.body.scopes ?: [];

		for ( var scope in scopes ) {
			systemOutput( "  Scope: #scope.name# (ref=#scope.variablesReference#)" );

			if ( scope.variablesReference > 0 && scope.name == "Local" ) {
				varsResponse = dap.getVariables( scope.variablesReference );
				vars = varsResponse.body.variables ?: [];
				for ( var v in vars ) {
					systemOutput( "    #v.name# = #v.value#" );
				}
			}
		}
	}

	// Continue execution
	systemOutput( "" );
	systemOutput( "Continuing execution..." );
	dap.continueThread( stoppedEvent.body.threadId );

	// Wait for HTTP request to complete
	threadJoin( "httpTrigger", 5000 );

	systemOutput( "" );
	if ( httpResult.keyExists( "error" ) ) {
		systemOutput( "HTTP request error: #httpResult.error#" );
	} else {
		systemOutput( "HTTP request completed: #httpResult.status ?: 'unknown'#" );
	}

	systemOutput( "" );
	systemOutput( "=== TEST COMPLETE ===" );

} catch ( any e ) {
	systemOutput( "" );
	systemOutput( "ERROR: #e.message#" );
	systemOutput( e.stackTrace );
} finally {
	dap.disconnect();
}
</cfscript>
