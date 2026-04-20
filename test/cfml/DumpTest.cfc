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
	variables.nullTargetFile = "";

	variables.lines = {
		debugLine: 35,       // variables-target.cfm
		nullDebugLine: 19    // null-target.cfm
	};

	function beforeAll() {
		setupDap();
		variables.targetFile = getArtifactPath( "variables-target.cfm" );
		variables.nullTargetFile = getArtifactPath( "null-target.cfm" );
	}

	function afterEach() {
		clearBreakpoints( variables.targetFile );
		clearBreakpoints( variables.nullTargetFile );
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

		expect( response.body.content ).toInclude( "name" );
		expect( response.body.content ).toInclude( "test" );
		expect( response.body.content ).toInclude( "123" );
		expect( response.body.content ).toInclude( "deep" );  // proves nested struct recurses

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

		expect( response.body.content ).toInclude( "four" );
		expect( response.body.content ).toInclude( "nested" );  // proves struct-in-array recurses

		cleanupThread( threadId );
	}

	function testDumpStruct_withNullField_doesNotCrash() {
		// Null-valued struct keys exercise the dump walker's handling of
		// structKeyExists=true / isNull=true entries.
		dap.setBreakpoints( variables.nullTargetFile, [ lines.nullDebugLine ] );
		triggerArtifact( "null-target.cfm" );

		var stopped = dap.waitForEvent( "stopped", 2000 );
		var threadId = stopped.body.threadId;

		var frame = getTopFrame( threadId );
		var localStruct = getVariableByName( getScopeByName( frame.id, "Local" ).variablesReference, "localStruct" );

		var response = dap.dump( localStruct.variablesReference );

		expect( response.body.content ).toInclude( "name" );
		expect( response.body.content ).toInclude( "test" );
		expect( response.body.content ).toInclude( "nullField" );  // null-valued key in dump

		expect( dap.threads() ).toHaveKey( "body" );

		cleanupThread( threadId );
	}

	function testDumpLocalScope_withNull_doesNotCrash() {
		// Scope-level dump is the realistic regression case — the Local scope contains
		// `localNull = nullValue()` alongside everything else. Pre-fix, walking a null entry
		// tripped the System.exit(1) catch path and killed the JVM.
		dap.setBreakpoints( variables.nullTargetFile, [ lines.nullDebugLine ] );
		triggerArtifact( "null-target.cfm" );

		var stopped = dap.waitForEvent( "stopped", 2000 );
		var threadId = stopped.body.threadId;

		var frame = getTopFrame( threadId );
		var localScopeRef = getScopeByName( frame.id, "Local" ).variablesReference;

		var response = dap.dump( localScopeRef );

		expect( response.body.content ).toInclude( "localNull" );    // null key present in scope dump
		expect( response.body.content ).toInclude( "localString" );  // other locals dumped alongside

		// Server still alive after walking a scope with a null entry.
		expect( dap.threads() ).toHaveKey( "body" );

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

		expect( isJSON( response.body.content ) ).toBeTrue();

		var parsed = deserializeJSON( response.body.content );
		expect( parsed.name ).toBe( "test" );
		expect( parsed.value ).toBe( 123 );
		expect( parsed.nested.deep ).toBe( "value" );

		cleanupThread( threadId );
	}

	function testDumpAsJSON_roundTripsArray() {
		dap.setBreakpoints( variables.targetFile, [ lines.debugLine ] );
		triggerArtifact( "variables-target.cfm" );

		var stopped = dap.waitForEvent( "stopped", 2000 );
		var threadId = stopped.body.threadId;

		var frame = getTopFrame( threadId );
		var localArray = getVariableByName( getScopeByName( frame.id, "Local" ).variablesReference, "localArray" );

		var response = dap.dumpAsJSON( localArray.variablesReference );

		expect( isJSON( response.body.content ) ).toBeTrue();

		var parsed = deserializeJSON( response.body.content );
		expect( parsed ).toBeArray();
		expect( parsed[ 1 ] ).toBe( 1 );
		expect( parsed[ 4 ] ).toBe( "four" );
		expect( parsed[ 5 ].nested ).toBeTrue();  // proves struct-in-array recurses

		cleanupThread( threadId );
	}

	function testDumpAsJSON_structWithNullField_roundTrips() {
		dap.setBreakpoints( variables.nullTargetFile, [ lines.nullDebugLine ] );
		triggerArtifact( "null-target.cfm" );

		var stopped = dap.waitForEvent( "stopped", 2000 );
		var threadId = stopped.body.threadId;

		var frame = getTopFrame( threadId );
		var localStruct = getVariableByName( getScopeByName( frame.id, "Local" ).variablesReference, "localStruct" );

		var response = dap.dumpAsJSON( localStruct.variablesReference );

		expect( isJSON( response.body.content ) ).toBeTrue();

		var parsed = deserializeJSON( response.body.content );
		expect( parsed.name ).toBe( "test" );
		expect( structKeyExists( parsed, "nullField" ) ).toBeTrue();  // null-valued key survives JSON round-trip
		expect( isNull( parsed.nullField ) ).toBeTrue();

		cleanupThread( threadId );
	}

	// ========== Server-survives-prior-error regression guard ==========

	function testServerSurvivesDumpCall_onBogusReference() {
		// Pre-fix, System.exit(1) in the dump catch killed the JVM on any dump error.
		// Pass a bogus variablesReference to force the error path, then prove server is still alive.
		dap.setBreakpoints( variables.targetFile, [ lines.debugLine ] );
		triggerArtifact( "variables-target.cfm" );

		var stopped = dap.waitForEvent( "stopped", 2000 );
		var threadId = stopped.body.threadId;

		var threw = false;
		try {
			dap.dump( -99999 );
		} catch ( DapClient.Error e ) {
			threw = true;
		}
		expect( threw ).toBeTrue();  // server rejected it at protocol level instead of crashing

		// If the JVM exited, this next call times out / the socket is dead.
		var threadsResponse = dap.threads();
		expect( threadsResponse ).toHaveKey( "body" );

		cleanupThread( threadId );
	}

	function testServerSurvivesDumpAsJSONCall_onBogusReference() {
		// Same regression guard as above, for the dumpAsJSON path.
		dap.setBreakpoints( variables.targetFile, [ lines.debugLine ] );
		triggerArtifact( "variables-target.cfm" );

		var stopped = dap.waitForEvent( "stopped", 2000 );
		var threadId = stopped.body.threadId;

		var threw = false;
		try {
			dap.dumpAsJSON( -99999 );
		} catch ( DapClient.Error e ) {
			threw = true;
		}
		expect( threw ).toBeTrue();

		var threadsResponse = dap.threads();
		expect( threadsResponse ).toHaveKey( "body" );

		cleanupThread( threadId );
	}

}
