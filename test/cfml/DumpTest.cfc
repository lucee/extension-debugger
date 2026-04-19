/**
 * Tests for DAP dump / dumpAsJSON custom requests.
 *
 * Regression guard for <https://dev.lucee.org/t/extension-debugger-crashes-lucee-6-when-dumping-a-variable/17209>:
 * pre-fix, dumping on Lucee 6.2 (agent mode) throws NoSuchMethodError inside the
 * javax/jakarta servlet-API mismatch, and System.exit(1) in the catch block kills
 * the host JVM. The strongest signal here is that the DAP server is still responsive
 * after the dump call.
 */
component extends="org.lucee.cfml.test.LuceeTestCase" labels="dap" {

	include "DapTestCase.cfm";

	variables.targetFile = "";

	variables.lines = {
		debugLine: 35  // var debugLine = "inspect here";
	};

	function beforeAll() {
		setupDap();
		variables.targetFile = getArtifactPath( "variables-target.cfm" );
	}

	function afterEach() {
		clearBreakpoints( variables.targetFile );
	}

	// ========== dump ==========

	function testDumpStruct_doesNotCrashServer() {
		dap.setBreakpoints( variables.targetFile, [ lines.debugLine ] );
		triggerArtifact( "variables-target.cfm" );

		var stopped = dap.waitForEvent( "stopped", 2000 );
		var threadId = stopped.body.threadId;

		var frame = getTopFrame( threadId );
		var localStruct = getVariableByName( getScopeByName( frame.id, "Local" ).variablesReference, "localStruct" );

		var response = dap.dump( localStruct.variablesReference );

		expect( response.body.content contains "something went wrong" ).toBeFalse();
		expect( response.body.content contains "dump failed" ).toBeFalse();
		expect( len( response.body.content ) ).toBeGT( 0 );

		// Sanity: server still alive — a second DAP call works.
		expect( dap.threads() ).toHaveKey( "body" );

		cleanupThread( threadId );
	}

	function testDumpArray_doesNotCrashServer() {
		dap.setBreakpoints( variables.targetFile, [ lines.debugLine ] );
		triggerArtifact( "variables-target.cfm" );

		var stopped = dap.waitForEvent( "stopped", 2000 );
		var threadId = stopped.body.threadId;

		var frame = getTopFrame( threadId );
		var localArray = getVariableByName( getScopeByName( frame.id, "Local" ).variablesReference, "localArray" );

		var response = dap.dump( localArray.variablesReference );

		expect( response.body.content contains "something went wrong" ).toBeFalse();
		expect( response.body.content contains "dump failed" ).toBeFalse();
		expect( len( response.body.content ) ).toBeGT( 0 );

		cleanupThread( threadId );
	}

	// ========== dumpAsJSON ==========

	function testDumpAsJSON_roundTripsStruct() {
		dap.setBreakpoints( variables.targetFile, [ lines.debugLine ] );
		triggerArtifact( "variables-target.cfm" );

		var stopped = dap.waitForEvent( "stopped", 2000 );
		var threadId = stopped.body.threadId;

		var frame = getTopFrame( threadId );
		var localStruct = getVariableByName( getScopeByName( frame.id, "Local" ).variablesReference, "localStruct" );

		var response = dap.dumpAsJSON( localStruct.variablesReference );

		expect( response.body.content contains "something went wrong" ).toBeFalse();
		expect( isJSON( response.body.content ) ).toBeTrue();

		var parsed = deserializeJSON( response.body.content );
		expect( parsed ).toHaveKey( "name" );
		expect( parsed.name ).toBe( "test" );

		cleanupThread( threadId );
	}

	// ========== Server-survives-prior-error regression guard ==========

	function testServerSurvivesDumpCall() {
		// Pre-fix, System.exit(1) in the dump catch killed the JVM.
		dap.setBreakpoints( variables.targetFile, [ lines.debugLine ] );
		triggerArtifact( "variables-target.cfm" );

		var stopped = dap.waitForEvent( "stopped", 2000 );
		var threadId = stopped.body.threadId;

		var frame = getTopFrame( threadId );
		var localStruct = getVariableByName( getScopeByName( frame.id, "Local" ).variablesReference, "localStruct" );

		// Swallow any dump-specific DAP error so we can still probe the server.
		try {
			dap.dump( localStruct.variablesReference );
		} catch ( any e ) {
			systemOutput( "dump threw (acceptable here): #e.message#", true );
		}

		// If the JVM exited, this next call times out / the socket is dead.
		var threadsResponse = dap.threads();
		expect( threadsResponse ).toHaveKey( "body" );

		cleanupThread( threadId );
	}

}
