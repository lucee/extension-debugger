/**
 * Tests for the variables scope on the top-level frame of a CFM included
 * by ModernAppListener._doInclude (Application.cfc with no onRequest).
 *
 * Red phase for the LDEV-6274 regression: when the INCLUDE frame is the
 * base of the debugger-frame stack (no enclosing UDF), `variables` lands
 * null and the Variables panel hides the page's own scope.
 *
 * Native-only — the bug is in Lucee core's DebuggerFrame INCLUDE constructor,
 * which doesn't exist in the agent's bytecode-instrumented frame model.
 */
component extends="org.lucee.cfml.test.LuceeTestCase" labels="dap" {

	include "DapTestCase.cfm";

	variables.targetFile = "";

	// Line numbers in artifacts/topLevelVariables/index.cfm — keep in sync.
	variables.lines = {
		debugLine: 3 // debugMarker = "stop here";
	};

	function beforeAll() {
		setupDap();
		variables.targetFile = getArtifactPath( "topLevelVariables/index.cfm" );
	}

	function run( testResults, testBox ) {
		describe( "DAP top-level CFM variables scope", function() {

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

			// LDEV-6274 regression: INCLUDE frame at base of stack (no enclosing
			// UDF) has null variables. Top-level CFM under Application.cfc with no
			// onRequest hits this path — ModernAppListener._doInclude pushes the
			// INCLUDE frame with enclosing=null.
			it( title="top-level CFM under Application.cfc reports variables scope at breakpoint", body=function() {
				dap.setBreakpoints( variables.targetFile, [ lines.debugLine ] );
				triggerArtifact( "topLevelVariables/index.cfm" );

				var stopped = dap.waitForEvent( "stopped", 2000 );
				var threadId = stopped.body.threadId;

				var frame = getTopFrame( threadId );
				var scopesResponse = dap.scopes( frame.id );
				var scopeNames = scopesResponse.body.scopes.map( function( s ) { return s.name; } );

				expect( scopeNames ).toInclude( "variables", "Top-level CFM should expose the variables scope (LDEV-6274 regression). Got: #serializeJSON( scopeNames )#" );

				cleanupThread( threadId );
			}, skip=!isNativeMode() );

			it( title="variables scope at a top-level breakpoint exposes page-level assignments", body=function() {
				dap.setBreakpoints( variables.targetFile, [ lines.debugLine ] );
				triggerArtifact( "topLevelVariables/index.cfm" );

				var stopped = dap.waitForEvent( "stopped", 2000 );
				var threadId = stopped.body.threadId;

				var frame = getTopFrame( threadId );
				var varsScope = getScopeByName( frame.id, "variables" );
				var varsResponse = dap.getVariables( varsScope.variablesReference );

				var varMap = {};
				for ( var v in varsResponse.body.variables ) {
					varMap[ v.name ] = v;
				}

				expect( varMap ).toHaveKey( "foo", "variables.foo was set on line 2 before the breakpoint" );
				expect( varMap.foo.value ).toBe( '"bar"' );

				cleanupThread( threadId );
			}, skip=!isNativeMode() );

			// Semantic boundary, not the bug: top-level CFML has no local scope
			// (`var x = 1` is illegal outside a UDF) and no arguments scope (no
			// function call). This passes today and must keep passing after the fix.
			it( title="top-level frame does NOT expose local or arguments scopes", body=function() {
				dap.setBreakpoints( variables.targetFile, [ lines.debugLine ] );
				triggerArtifact( "topLevelVariables/index.cfm" );

				var stopped = dap.waitForEvent( "stopped", 2000 );
				var threadId = stopped.body.threadId;

				var frame = getTopFrame( threadId );
				var scopesResponse = dap.scopes( frame.id );
				var scopeNames = scopesResponse.body.scopes.map( function( s ) { return s.name; } );

				expect( scopeNames ).notToInclude( "local", "Top-level CFM has no local scope" );
				expect( scopeNames ).notToInclude( "arguments", "Top-level CFM has no arguments scope" );

				cleanupThread( threadId );
			}, skip=!isNativeMode() );

		} );
	}
}
