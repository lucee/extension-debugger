/**
 * Tests for variables and scopes inspection.
 *
 * BDD style — skip=notSupportsBreakpointLocations() on capability-gated specs.
 */
component extends="org.lucee.cfml.test.LuceeTestCase" labels="dap" {

	include "DapTestCase.cfm";

	variables.targetFile = "";

	// Line numbers in variables-target.cfm — keep in sync with the file.
	variables.lines = {
		debugLine: 35  // var debugLine = "inspect here";
	};

	function beforeAll() {
		setupDap();
		variables.targetFile = getArtifactPath( "variables-target.cfm" );
	}

	function run( testResults, testBox ) {
		describe( "DAP variables + scopes", function() {

			beforeEach( function() {
				dap.drainEvents();
			} );

			afterEach( function() {
				clearBreakpoints( variables.targetFile );

				for ( var threadId in dap.getSuspendedThreadIds() ) {
					try {
						dap.continueThread( threadId );
					} catch ( any e ) {
						systemOutput( "afterEach: continue thread #threadId# ignored: #e.message#", true );
					}
				}

				try {
					waitForHttpComplete( 3000 );
				} catch ( any e ) {
					systemOutput( "afterEach: http drain timeout ignored: #e.message#", true );
				}

				dap.drainEvents();
			} );

			it( title="native: target debugLine is a valid breakpoint location", body=function() {
				var locations = dap.breakpointLocations( variables.targetFile, 1, 45 );
				var validLines = locations.body.breakpoints.map( function( bp ) { return bp.line; } );

				systemOutput( "#variables.targetFile# valid lines: #serializeJSON( validLines )#", true );

				for ( var key in variables.lines ) {
					var line = variables.lines[ key ];
					expect( validLines ).toInclude( line, "#variables.targetFile# line #line# (#key#) should be a valid breakpoint location" );
				}
			}, skip=notSupportsBreakpointLocations() );

			it( "reports Local and Arguments scopes at a UDF breakpoint", function() {
				dap.setBreakpoints( variables.targetFile, [ lines.debugLine ] );
				triggerArtifact( "variables-target.cfm" );

				var stopped = dap.waitForEvent( "stopped", 2000 );
				var threadId = stopped.body.threadId;

				var frame = getTopFrame( threadId );
				var scopesResponse = dap.scopes( frame.id );
				var scopeNames = scopesResponse.body.scopes.map( function( s ) { return s.name; } );

				expect( scopeNames ).toInclude( "Local", "Should have Local scope" );
				expect( scopeNames ).toInclude( "Arguments", "Should have Arguments scope" );

				cleanupThread( threadId );
			} );

			it( "local scope exposes typed variable values (string/number/boolean) with expandable refs for struct + array", function() {
				dap.setBreakpoints( variables.targetFile, [ lines.debugLine ] );
				triggerArtifact( "variables-target.cfm" );

				var stopped = dap.waitForEvent( "stopped", 2000 );
				var threadId = stopped.body.threadId;

				var frame = getTopFrame( threadId );
				var localScope = getScopeByName( frame.id, "Local" );
				var varsResponse = dap.getVariables( localScope.variablesReference );

				var varMap = {};
				for ( var v in varsResponse.body.variables ) {
					varMap[ v.name ] = v;
				}

				expect( varMap ).toHaveKey( "localString" );
				expect( varMap.localString.value ).toBe( '"hello"' );

				expect( varMap ).toHaveKey( "localNumber" );
				expect( varMap.localNumber.value ).toBe( "42" );

				expect( varMap ).toHaveKey( "localBoolean" );
				expect( varMap.localBoolean.value.lcase() ).toBe( "true" );

				expect( varMap ).toHaveKey( "localArray" );
				expect( varMap.localArray.variablesReference ).toBeGT( 0, "Array should be expandable" );

				expect( varMap ).toHaveKey( "localStruct" );
				expect( varMap.localStruct.variablesReference ).toBeGT( 0, "Struct should be expandable" );

				cleanupThread( threadId );
			} );

			it( "arguments scope exposes the call's argument values", function() {
				dap.setBreakpoints( variables.targetFile, [ lines.debugLine ] );
				triggerArtifact( "variables-target.cfm" );

				var stopped = dap.waitForEvent( "stopped", 2000 );
				var threadId = stopped.body.threadId;

				var frame = getTopFrame( threadId );
				var argsScope = getScopeByName( frame.id, "Arguments" );
				var varsResponse = dap.getVariables( argsScope.variablesReference );

				var varMap = {};
				for ( var v in varsResponse.body.variables ) {
					varMap[ v.name ] = v;
				}

				expect( varMap ).toHaveKey( "arg1" );
				expect( varMap.arg1.value ).toBe( '"arg-value"' );

				expect( varMap ).toHaveKey( "arg2" );
				expect( varMap.arg2.value ).toBe( "999" );

				cleanupThread( threadId );
			} );

			it( "expands a nested struct through two levels (localStruct.nested.deep)", function() {
				dap.setBreakpoints( variables.targetFile, [ lines.debugLine ] );
				triggerArtifact( "variables-target.cfm" );

				var stopped = dap.waitForEvent( "stopped", 2000 );
				var threadId = stopped.body.threadId;

				var frame = getTopFrame( threadId );
				var localScope = getScopeByName( frame.id, "Local" );
				var varsResponse = dap.getVariables( localScope.variablesReference );

				var localStruct = {};
				for ( var v in varsResponse.body.variables ) {
					if ( v.name == "localStruct" ) {
						localStruct = v;
						break;
					}
				}

				expect( localStruct.variablesReference ).toBeGT( 0, "localStruct should be expandable" );

				var nestedResponse = dap.getVariables( localStruct.variablesReference );
				var nestedMap = {};
				for ( var v in nestedResponse.body.variables ) {
					nestedMap[ v.name ] = v;
				}

				expect( nestedMap ).toHaveKey( "name" );
				expect( nestedMap ).toHaveKey( "nested" );
				expect( nestedMap.nested.variablesReference ).toBeGT( 0, "nested should be expandable" );

				var deepResponse = dap.getVariables( nestedMap.nested.variablesReference );
				var deepMap = {};
				for ( var v in deepResponse.body.variables ) {
					deepMap[ v.name ] = v;
				}

				expect( deepMap ).toHaveKey( "deep" );
				expect( deepMap.deep.value ).toBe( '"value"' );

				cleanupThread( threadId );
			} );

			it( "expands an array, exposing indexed-element values", function() {
				dap.setBreakpoints( variables.targetFile, [ lines.debugLine ] );
				triggerArtifact( "variables-target.cfm" );

				var stopped = dap.waitForEvent( "stopped", 2000 );
				var threadId = stopped.body.threadId;

				var frame = getTopFrame( threadId );
				var localScope = getScopeByName( frame.id, "Local" );
				var varsResponse = dap.getVariables( localScope.variablesReference );

				var localArray = {};
				for ( var v in varsResponse.body.variables ) {
					if ( v.name == "localArray" ) {
						localArray = v;
						break;
					}
				}

				expect( localArray.variablesReference ).toBeGT( 0, "localArray should be expandable" );

				var arrayResponse = dap.getVariables( localArray.variablesReference );
				var arrayVars = arrayResponse.body.variables;

				expect( arrayVars.len() ).toBeGTE( 5, "Array should have at least 5 elements, got #arrayVars.len()#: #serializeJSON( arrayVars )#" );

				var arrayMap = {};
				for ( var v in arrayVars ) {
					arrayMap[ v.name ] = v;
				}

				expect( arrayMap[ "1" ].value ).toBe( "1" );
				expect( arrayMap[ "2" ].value ).toBe( "2" );
				expect( arrayMap[ "4" ].value ).toBe( '"four"' );

				cleanupThread( threadId );
			} );

		} );
	}
}
