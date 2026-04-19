/**
 * Tests for DAP getMetadata custom request.
 *
 * Native mode: calls lucee.runtime.functions.system.GetMetaData via reflection
 * and returns JSON-serialized metadata.
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
		expect( response.body.content contains "getMetadata failed" ).toBeFalse();
		expect( response.body.content contains "Error:" ).toBeFalse();

		var parsed = deserializeJSON( response.body.content );

		if ( isNativeMode() ) {
			// Native returns a serialized GetMetaData result — typically a struct.
			expect( parsed ).toBeTypeOf( "struct" );
		} else {
			// Agent / JDWP mode returns a static "not supported" string.
			expect( parsed ).toBe( "getMetadata not supported in JDWP mode" );
		}

		// Sanity: server still alive after the call.
		expect( dap.threads() ).toHaveKey( "body" );

		cleanupThread( threadId );
	}

}
