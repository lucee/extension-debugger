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
		// structKeyList-enumerable but isNull=true entries.
		dap.setBreakpoints( variables.nullTargetFile, [ lines.nullDebugLine ] );
		triggerArtifact( "null-target.cfm" );

		var stopped = dap.waitForEvent( "stopped", 2000 );
		var threadId = stopped.body.threadId;

		var frame = getTopFrame( threadId );
		var localStruct = getVariableByName( getScopeByName( frame.id, "Local" ).variablesReference, "localStruct" );

		var response = dap.dump( localStruct.variablesReference );

		expect( response.body.content ).toInclude( "name" );
		expect( response.body.content ).toInclude( "test" );

		// Server still alive after walking a struct with a null entry.
		expect( dap.threads() ).toHaveKey( "body" );

		cleanupThread( threadId );
	}

	function testDumpLocalScope_withNull_doesNotCrash() {
		// Scope-level dump walker survives a null local alongside non-null locals.
		// Pre-fix, walking a null entry tripped the System.exit(1) catch path and killed the JVM.
		// Note: agent-mode JDWP enumeration strips null entries before they reach the dump walker,
		// so we only assert server-survival + a non-null sibling is present, not localNull itself.
		dap.setBreakpoints( variables.nullTargetFile, [ lines.nullDebugLine ] );
		triggerArtifact( "null-target.cfm" );

		var stopped = dap.waitForEvent( "stopped", 2000 );
		var threadId = stopped.body.threadId;

		var frame = getTopFrame( threadId );
		var localScopeRef = getScopeByName( frame.id, "Local" ).variablesReference;

		var response = dap.dump( localScopeRef );

		expect( response.body.content ).toInclude( "localString" );  // non-null local present

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
		// Null-valued key survives round-trip: in Lucee 7, structKeyExists() returns false
		// for null values, but the key is enumerable via structKeyList() and the value isNull.
		expect( structKeyList( parsed ) ).toInclude( "nullField" );
		expect( isNull( parsed.nullField ?: nullValue() ) ).toBeTrue();

		cleanupThread( threadId );
	}

	// ========== Server-survives-prior-error regression guard ==========

	function testServerSurvivesDumpCall_onBogusReference() {
		// Pre-fix, System.exit(1) in the dump catch killed the JVM on any dump error.
		// A bogus variablesReference takes the graceful early-return path ("Variable not found"),
		// but the call must still complete cleanly and the server must remain responsive.
		dap.setBreakpoints( variables.targetFile, [ lines.debugLine ] );
		triggerArtifact( "variables-target.cfm" );

		var stopped = dap.waitForEvent( "stopped", 2000 );
		var threadId = stopped.body.threadId;

		var response = dap.dump( -99999 );
		// Native: "Variable not found", Agent: "Lookup of ref having ID -99999 found nothing."
		expect( reFindNoCase( "not found|found nothing", response.body.content ) ).toBeGT( 0 );

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

		var response = dap.dumpAsJSON( -99999 );
		expect( reFindNoCase( "not found|found nothing", response.body.content ) ).toBeGT( 0 );

		var threadsResponse = dap.threads();
		expect( threadsResponse ).toHaveKey( "body" );

		cleanupThread( threadId );
	}

}
