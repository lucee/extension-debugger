/**
 * Line breakpoints inside catch / onError bodies.
 *
 * Separate from uncaught-exception breakpoints — these are normal line BPs
 * placed inside catch-body and Application.cfc onError handlers. Verifies
 * the user can land there, see the enclosing function's frames, and
 * inspect the exception that was caught / passed in.
 */
component extends="org.lucee.cfml.test.LuceeTestCase" labels="dap" {

	include "DapTestCase.cfm";

	variables.catchTargetFile = "";
	variables.onErrorAppCfc = "";

	// Keep these in sync with the catch-body target artifact.
	variables.catchBodyLine = 20;
	variables.rethrowLine = 22;
	variables.onErrorLine = 6;

	function beforeAll() {
		setupDap();
		variables.catchTargetFile = getArtifactPath( "exception-catch-body-target.cfm" );
		variables.onErrorAppCfc = getArtifactPath( "exceptionInOnError/Application.cfc" );
	}

	function run( testResults, testBox ) {
		describe( "DAP catch / onError line breakpoints", function() {

			beforeEach( function() {
				dap.drainEvents();
			} );

			afterEach( function() {
				dap.clearAllKnownBreakpoints();

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

			it( "BP inside catch body stops with intact frames and 'e' visible", function() {
				dap.setBreakpoints( variables.catchTargetFile, [ variables.catchBodyLine ] );

				triggerArtifact( "exception-catch-body-target.cfm" );

				var stopped = dap.waitForEvent( "stopped", 2000 );
				expect( stopped.body.reason ).toBe( "breakpoint" );
				var threadId = stopped.body.threadId;

				var frames = dap.stackTrace( threadId ).body.stackFrames;
				expect( frames.len() ).toBeGTE( 2, "catch body should run in caller frame + include frame" );
				expect( frames[ 1 ].name ).toInclude( "caller" );
				expect( frames[ 1 ].line ).toBe( variables.catchBodyLine );

				var localScope = getScopeByName( frames[ 1 ].id, "Local" );
				var vars = dap.getVariables( localScope.variablesReference ).body.variables;
				var names = vars.map( function( v ) { return v.name; } );
				expect( names ).toInclude( "e", "catch variable 'e' should be exposed in Local scope" );

				cleanupThread( threadId );
			} );

			it( "BP on rethrow line stops BEFORE unwinding", function() {
				dap.setBreakpoints( variables.catchTargetFile, [ variables.rethrowLine ] );

				triggerArtifact( "exception-catch-body-target.cfm", { rethrow: true }, true );

				var stopped = dap.waitForEvent( "stopped", 2000 );
				expect( stopped.body.reason ).toBe( "breakpoint" );
				var threadId = stopped.body.threadId;

				var frames = dap.stackTrace( threadId ).body.stackFrames;
				expect( frames.len() ).toBeGTE( 2, "rethrow line should still have caller + include frames" );
				expect( frames[ 1 ].line ).toBe( variables.rethrowLine );

				cleanupThread( threadId );
			} );

			it( "BP inside Application.cfc onError stops during error handling", function() {
				dap.setBreakpoints( variables.onErrorAppCfc, [ variables.onErrorLine ] );

				var requestUrl = getArtifactUrl( "exceptionInOnError/index.cfm" );
				variables.httpResult = {};
				variables.httpThread = "httpTrigger_" & createUUID();
				thread name="#variables.httpThread#" requestUrl=requestUrl httpResult=variables.httpResult {
					try {
						http url="#attributes.requestUrl#" result="local.r" timeout=5 throwonerror=false;
						httpResult.status = local.r.statusCode;
						httpResult.content = local.r.fileContent;
					} catch ( any e ) {
						httpResult.error = e.message;
					}
				}

				var stopped = dap.waitForEvent( "stopped", 3000 );
				expect( stopped.body.reason ).toBe( "breakpoint" );
				var threadId = stopped.body.threadId;

				var frames = dap.stackTrace( threadId ).body.stackFrames;
				expect( frames.len() ).toBeGTE( 1, "onError body should expose at least its own frame" );
				expect( frames[ 1 ].name ).toInclude( "onError" );
				_expectPathEndsWith( frames[ 1 ].source.path, "Application.cfc" );

				var argsScope = getScopeByName( frames[ 1 ].id, "Arguments" );
				var argVars = dap.getVariables( argsScope.variablesReference ).body.variables;
				var argNames = argVars.map( function( v ) { return v.name; } );
				expect( argNames ).toInclude( "exception", "onError's exception argument should be exposed" );

				cleanupThread( threadId );
			} );

		} );
	}
}
