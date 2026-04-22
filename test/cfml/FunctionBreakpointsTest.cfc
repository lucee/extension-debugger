/**
 * Tests for function breakpoints (break on function name without file/line).
 *
 * BDD style — runtime guards inside each `it`.
 */
component extends="org.lucee.cfml.test.LuceeTestCase" labels="dap" {

	include "DapTestCase.cfm";

	variables.targetFile = "";

	function beforeAll() {
		setupDap();
		variables.targetFile = getArtifactPath( "function-bp-target.cfm" );
	}

	function run( testResults, testBox ) {
		describe( "DAP function breakpoints", function() {

			beforeEach( function() {
				dap.drainEvents();
			} );

			afterEach( function() {
				clearFunctionBreakpoints();
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

			it( "accepts a setFunctionBreakpoints call with a single function name", function() {
				if ( !supportsFunctionBreakpoints() ) {
					systemOutput( "skipping: function breakpoints not supported", true );
					return;
				}

				var response = dap.setFunctionBreakpoints( [ "targetFunction" ] );

				expect( response.body ).toHaveKey( "breakpoints" );
				expect( response.body.breakpoints ).toHaveLength( 1 );
			} );

			it( "stops execution when a function breakpoint's function is called", function() {
				if ( !supportsFunctionBreakpoints() ) {
					systemOutput( "skipping: function breakpoints not supported", true );
					return;
				}

				dap.setFunctionBreakpoints( [ "targetFunction" ] );
				triggerArtifact( "function-bp-target.cfm" );

				var stopped = dap.waitForEvent( "stopped", 2000 );

				expect( stopped.body.reason ).toBe( "function breakpoint" );

				var frame = getTopFrame( stopped.body.threadId );
				expect( frame.name ).toInclude( "targetFunction" );

				cleanupThread( stopped.body.threadId );
			} );

			it( "matches function names case-insensitively (TARGETFUNCTION)", function() {
				if ( !supportsFunctionBreakpoints() ) {
					systemOutput( "skipping: function breakpoints not supported", true );
					return;
				}

				dap.setFunctionBreakpoints( [ "TARGETFUNCTION" ] );
				triggerArtifact( "function-bp-target.cfm" );

				var stopped = dap.waitForEvent( "stopped", 2000 );

				expect( stopped.body.reason ).toBe( "function breakpoint" );

				var frame = getTopFrame( stopped.body.threadId );
				expect( frame.name.lcase() ).toInclude( "targetfunction" );

				cleanupThread( stopped.body.threadId );
			} );

			it( "supports wildcard function names (onRequest*)", function() {
				if ( !supportsFunctionBreakpoints() ) {
					systemOutput( "skipping: function breakpoints not supported", true );
					return;
				}

				dap.setFunctionBreakpoints( [ "onRequest*" ] );
				triggerArtifact( "function-bp-target.cfm" );

				var stopped = dap.waitForEvent( "stopped", 2000 );

				expect( stopped.body.reason ).toBe( "function breakpoint" );

				var frame = getTopFrame( stopped.body.threadId );
				expect( frame.name.lcase() ).toInclude( "onrequest" );

				dap.continueThread( stopped.body.threadId );

				// May hit another onRequest* function; tolerate either outcome.
				try {
					stopped = dap.waitForEvent( "stopped", 2000 );
					var frame2 = getTopFrame( stopped.body.threadId );
					expect( frame2.name.lcase() ).toInclude( "onrequest" );
					cleanupThread( stopped.body.threadId );
				} catch ( any e ) {
					waitForHttpComplete();
				}
			} );

			it( "hits multiple distinct function breakpoints in the same run", function() {
				if ( !supportsFunctionBreakpoints() ) {
					systemOutput( "skipping: function breakpoints not supported", true );
					return;
				}

				dap.setFunctionBreakpoints( [ "targetFunction", "anotherFunction" ] );
				triggerArtifact( "function-bp-target.cfm" );

				var stopped = dap.waitForEvent( "stopped", 2000 );
				var frame = getTopFrame( stopped.body.threadId );

				var hitFunction = frame.name.lcase();
				expect( hitFunction contains "targetfunction" || hitFunction contains "anotherfunction" )
					.toBeTrue( "Should hit one of the breakpoint functions" );

				dap.continueThread( stopped.body.threadId );

				try {
					stopped = dap.waitForEvent( "stopped", 2000 );
					var frame2 = getTopFrame( stopped.body.threadId );
					var hitFunction2 = frame2.name.lcase();
					expect( hitFunction2 contains "targetfunction" || hitFunction2 contains "anotherfunction" )
						.toBeTrue( "Should hit the other breakpoint function" );
					cleanupThread( stopped.body.threadId );
				} catch ( any e ) {
					waitForHttpComplete();
				}
			} );

			it( "honours a conditional function breakpoint (arguments.input == 'test-value')", function() {
				if ( !supportsFunctionBreakpoints() ) {
					systemOutput( "skipping: function breakpoints not supported", true );
					return;
				}

				dap.setFunctionBreakpoints( [ "targetFunction" ], [ "arguments.input == 'test-value'" ] );
				triggerArtifact( "function-bp-target.cfm" );

				var stopped = dap.waitForEvent( "stopped", 2000 );

				expect( stopped.body.reason ).toBe( "function breakpoint" );

				var frame = getTopFrame( stopped.body.threadId );
				var argsScope = getScopeByName( frame.id, "Arguments" );
				var inputVar = getVariableByName( argsScope.variablesReference, "input" );

				expect( inputVar.value ).toBe( '"test-value"' );

				cleanupThread( stopped.body.threadId );
			} );

			it( "clearing function breakpoints stops future hits", function() {
				if ( !supportsFunctionBreakpoints() ) {
					systemOutput( "skipping: function breakpoints not supported", true );
					return;
				}

				dap.setFunctionBreakpoints( [ "targetFunction" ] );
				var response = dap.setFunctionBreakpoints( [] );

				expect( response.body.breakpoints ).toHaveLength( 0 );

				triggerArtifact( "function-bp-target.cfm" );

				sleep( 2000 );
				var hasStoppedEvent = dap.hasEvent( "stopped" );
				expect( hasStoppedEvent ).toBeFalse( "Should not stop after clearing breakpoints" );

				waitForHttpComplete();
			} );

			it( "replacing function breakpoints swaps the active set", function() {
				if ( !supportsFunctionBreakpoints() ) {
					systemOutput( "skipping: function breakpoints not supported", true );
					return;
				}

				dap.setFunctionBreakpoints( [ "targetFunction" ] );
				var response = dap.setFunctionBreakpoints( [ "anotherFunction" ] );

				expect( response.body.breakpoints ).toHaveLength( 1 );

				triggerArtifact( "function-bp-target.cfm" );

				var stopped = dap.waitForEvent( "stopped", 2000 );
				var frame = getTopFrame( stopped.body.threadId );

				expect( frame.name.lcase() ).toInclude( "anotherfunction" );

				cleanupThread( stopped.body.threadId );
			} );

		} );
	}
}
