<cfscript>
// Test DAP threads() command
// Run this from a DIFFERENT Lucee instance than the one being debugged

systemOutput( "=== DAP Threads Test ===", true );

dap = new DapClient( debug=true );

try {
	dap.connect( "localhost", 10000 );

	// Initialize
	systemOutput( "Sending initialize...", true );
	result = dap.initialize();
	systemOutput( "Initialize response: " & serializeJSON( result ), true );

	// Get threads
	systemOutput( "Sending threads...", true );
	result = dap.threads();
	systemOutput( "Threads response: " & serializeJSON( result ), true );

	if ( structKeyExists( result, "body" ) && structKeyExists( result.body, "threads" ) ) {
		systemOutput( "Found #result.body.threads.len()# threads:", true );
		for ( var t in result.body.threads ) {
			systemOutput( "  - [#t.id#] #t.name#", true );
		}
	} else {
		systemOutput( "No threads in response!", true );
	}

	dap.dapDisconnect();
} catch ( any e ) {
	systemOutput( "ERROR: #e.message#", true );
	systemOutput( e.stackTrace, true );
} finally {
	dap.disconnect();
}

systemOutput( "=== Test Complete ===", true );
</cfscript>
