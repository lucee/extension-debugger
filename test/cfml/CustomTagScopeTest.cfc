/**
 * Custom tag (cfmodule) variables-scope semantics at a breakpoint.
 *
 * CFML semantics: a custom tag has its own isolated `variables` scope —
 * `<cfmodule template="widget.cfm">` runs widget.cfm with a fresh variables
 * scope; the caller's scope is exposed separately as `caller`. At a
 * breakpoint inside widget.cfm the Variables panel must therefore show the
 * MODULE's variables, not the caller's.
 *
 * Today the INCLUDE constructor at PageContextImpl.java:3576 inherits
 * `enclosing.variables` whenever an enclosing frame exists — for cfmodule
 * that's the caller's variables scope, which leaks across the tag boundary.
 *
 * Red-phase probe — expected to fail until the constructor (or the call
 * sites) start passing the live `pc.variablesScope()` for every INCLUDE
 * push, not just when enclosing is null.
 */
component extends="org.lucee.cfml.test.LuceeTestCase" labels="dap" {

	include "DapTestCase.cfm";

	variables.targetFile = "";

	// Line numbers in artifacts/cfmoduleScope/widget.cfm — keep in sync.
	variables.lines = {
		debugLine: 4 // debugMarker = "stop here";
	};

	function beforeAll() {
		setupDap();
		variables.targetFile = getArtifactPath( "cfmoduleScope/widget.cfm" );
	}

	function run( testResults, testBox ) {
		describe( "DAP cfmodule variables-scope isolation", function() {

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

			it( title="cfmodule body variables scope contains the module's own assignments", body=function() {
				dap.setBreakpoints( variables.targetFile, [ lines.debugLine ] );
				triggerArtifact( "cfmoduleScope/index.cfm" );

				var stopped = dap.waitForEvent( "stopped", 2000 );
				var threadId = stopped.body.threadId;

				var frame = getTopFrame( threadId );
				var varsScope = getScopeByName( frame.id, "variables" );
				var varsResponse = dap.getVariables( varsScope.variablesReference );

				var varMap = {};
				for ( var v in varsResponse.body.variables ) {
					varMap[ v.name ] = v;
				}

				expect( varMap ).toHaveKey( "moduleVar", "cfmodule body should see its own variables. Got keys: #serializeJSON( structKeyArray( varMap ) )#" );
				expect( varMap.moduleVar.value ).toBe( '"module-only"' );

				cleanupThread( threadId );
			}, skip=!isNativeMode() );

			it( title="cfmodule body variables scope does NOT leak the caller's variables", body=function() {
				dap.setBreakpoints( variables.targetFile, [ lines.debugLine ] );
				triggerArtifact( "cfmoduleScope/index.cfm" );

				var stopped = dap.waitForEvent( "stopped", 2000 );
				var threadId = stopped.body.threadId;

				var frame = getTopFrame( threadId );
				var varsScope = getScopeByName( frame.id, "variables" );
				var varsResponse = dap.getVariables( varsScope.variablesReference );

				var varMap = {};
				for ( var v in varsResponse.body.variables ) {
					varMap[ v.name ] = v;
				}

				expect( varMap ).notToHaveKey( "callerVar", "Caller's variables must not leak into custom-tag variables scope. Got keys: #serializeJSON( structKeyArray( varMap ) )#" );

				cleanupThread( threadId );
			}, skip=!isNativeMode() );

		} );
	}
}
