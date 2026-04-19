/**
 * Tests for DAP getMetadata custom request.
 *
 * Native mode: calls lucee.runtime.functions.system.GetMetaData via reflection
 * and returns JSON-serialized metadata (or a JSON-encoded error string if
 * GetMetaData throws for the target type).
 * Agent / JDWP mode: returns the literal JSON string "getMetadata not supported in JDWP mode".
 */
component extends="org.lucee.cfml.test.LuceeTestCase" labels="dap" {

	include "DapTestCase.cfm";

	variables.targetFile = "";

	variables.lines = {
		debugLine: 35
	};

	function beforeAll() {
		setupDap();
		variables.targetFile = getArtifactPath( "variables-target.cfm" );
	}

	function afterEach() {
		clearBreakpoints( variables.targetFile );
	}

	function testGetMetadata_returnsValidJson() {
		dap.setBreakpoints( variables.targetFile, [ lines.debugLine ] );
		triggerArtifact( "variables-target.cfm" );

		var stopped = dap.waitForEvent( "stopped", 2000 );
		var threadId = stopped.body.threadId;

		var frame = getTopFrame( threadId );
		var localStruct = getVariableByName( getScopeByName( frame.id, "Local" ).variablesReference, "localStruct" );

		var response = dap.getMetadata( localStruct.variablesReference );

		expect( isJSON( response.body.content ) ).toBeTrue();

		if ( !isNativeMode() ) {
			// Agent / JDWP mode is a stub - returns a fixed marker string.
			expect( deserializeJSON( response.body.content ) ).toBe( "getMetadata not supported in JDWP mode" );
		}

		// Regression guard: server still responsive after the call.
		expect( dap.threads() ).toHaveKey( "body" );

		cleanupThread( threadId );
	}

}
