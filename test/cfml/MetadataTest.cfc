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
	variables.componentTargetFile = "";

	variables.lines = {
		debugLine: 35,           // variables-target.cfm
		componentDebugLine: 9    // metadata-component-target.cfm
	};

	function beforeAll() {
		setupDap();
		variables.targetFile = getArtifactPath( "variables-target.cfm" );
		variables.componentTargetFile = getArtifactPath( "metadata-component-target.cfm" );
	}

	function afterEach() {
		clearBreakpoints( variables.targetFile );
		clearBreakpoints( variables.componentTargetFile );
	}

	function testGetMetadata_returnsValidJson() {
		dap.setBreakpoints( variables.targetFile, [ lines.debugLine ] );
		triggerArtifact( "variables-target.cfm" );

		var stopped = dap.waitForEvent( "stopped", 2000 );
		var threadId = stopped.body.threadId;

		var frame = getTopFrame( threadId );
		var localStruct = getVariableByName( getScopeByName( frame.id, "Local" ).variablesReference, "localStruct" );

		var response = dap.getMetadata( localStruct.variablesReference );

		systemOutput( "getMetadata content: #response.body.content#", true );

		expect( isJSON( response.body.content ) ).toBeTrue();
		var parsed = deserializeJSON( response.body.content );

		if ( isNativeMode() ) {
			// Native should return GetMetaData's result serialized - a struct.
			// Any JSON string (e.g. "Error: ..." or "getMetadata failed") means a fallback fired.
			expect( parsed ).toBeTypeOf( "struct" );
		} else {
			// Agent / JDWP mode is a stub - returns a fixed marker string.
			expect( parsed ).toBe( "getMetadata not supported in JDWP mode" );
		}

		// Regression guard: server still responsive after the call.
		expect( dap.threads() ).toHaveKey( "body" );

		cleanupThread( threadId );
	}

	function testGetMetadata_onComponent_returnsFunctionAndPropertyMetadata() {
		dap.setBreakpoints( variables.componentTargetFile, [ lines.componentDebugLine ] );
		triggerArtifact( "metadata-component-target.cfm" );

		var stopped = dap.waitForEvent( "stopped", 2000 );
		var threadId = stopped.body.threadId;

		var frame = getTopFrame( threadId );
		var localComponent = getVariableByName( getScopeByName( frame.id, "Local" ).variablesReference, "localComponent" );

		var response = dap.getMetadata( localComponent.variablesReference );

		expect( isJSON( response.body.content ) ).toBeTrue();
		var parsed = deserializeJSON( response.body.content );

		if ( isNativeMode() ) {
			expect( parsed ).toBeTypeOf( "struct" );
			expect( parsed.name ).toMatch( "\.SampleComponent$" );  // Lucee returns the fully-qualified name

			// greet() function surfaces with correct signature.
			var greetFns = parsed.functions.filter( ( fn ) => fn.name == "greet" );
			expect( arrayLen( greetFns ) ).toBe( 1 );
			var greet = greetFns[ 1 ];
			expect( greet.returntype ).toBe( "string" );
			expect( greet.access ).toBe( "public" );
			expect( arrayLen( greet.parameters ) ).toBe( 1 );
			expect( greet.parameters[ 1 ].name ).toBe( "who" );
			expect( greet.parameters[ 1 ].required ).toBeTrue();

			// accessor-backed `foo` property surfaces with its declared type.
			var fooProps = parsed.properties.filter( ( p ) => p.name == "foo" );
			expect( arrayLen( fooProps ) ).toBe( 1 );
			expect( fooProps[ 1 ].type ).toBe( "string" );
		} else {
			// Agent / JDWP mode — stub path must not JVM-exit.
			expect( parsed ).toBe( "getMetadata not supported in JDWP mode" );
		}

		expect( dap.threads() ).toHaveKey( "body" );

		cleanupThread( threadId );
	}

}
