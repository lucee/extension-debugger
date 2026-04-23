/**
 * Tests for evaluate/expression functionality.
 *
 * BDD style — skip= uses capabilities probed at include-time via DapTestCase.cfm.
 */
component extends="org.lucee.cfml.test.LuceeTestCase" labels="dap" {

	include "DapTestCase.cfm";

	variables.targetFile = "";

	// Line numbers in evaluate-target.cfm — keep in sync with the file.
	variables.lines = {
		debugLine: 26  // return localVar & " - " & dataName;
	};

	function beforeAll() {
		setupDap();
		variables.targetFile = getArtifactPath( "evaluate-target.cfm" );
	}

	function run( testResults, testBox ) {
		describe( "DAP evaluate", function() {

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
				var locations = dap.breakpointLocations( variables.targetFile, 1, 40 );
				var validLines = locations.body.breakpoints.map( function( bp ) { return bp.line; } );

				systemOutput( "#variables.targetFile# valid lines: #serializeJSON( validLines )#", true );

				for ( var key in variables.lines ) {
					var line = variables.lines[ key ];
					expect( validLines ).toInclude( line, "#variables.targetFile# line #line# (#key#) should be a valid breakpoint location" );
				}
			}, skip=notSupportsBreakpointLocations() );

			it( title="evaluates a simple arithmetic expression", body=function() {
				dap.setBreakpoints( variables.targetFile, [ lines.debugLine ] );
				triggerArtifact( "evaluate-target.cfm" );

				var stopped = dap.waitForEvent( "stopped", 2000 );
				var threadId = stopped.body.threadId;
				var frame = getTopFrame( threadId );

				var evalResponse = dap.evaluate( frame.id, "1 + 1" );

				expect( evalResponse.body.result ).toBe( "2" );

				cleanupThread( threadId );
			}, skip=notSupportsEvaluate() );

			it( title="evaluates a local string variable", body=function() {
				dap.setBreakpoints( variables.targetFile, [ lines.debugLine ] );
				triggerArtifact( "evaluate-target.cfm" );

				var stopped = dap.waitForEvent( "stopped", 2000 );
				var threadId = stopped.body.threadId;
				var frame = getTopFrame( threadId );

				var evalResponse = dap.evaluate( frame.id, "localVar" );

				expect( evalResponse.body.result ).toBe( '"local-value"' );

				cleanupThread( threadId );
			}, skip=notSupportsEvaluate() );

			it( title="evaluates a local numeric variable", body=function() {
				dap.setBreakpoints( variables.targetFile, [ lines.debugLine ] );
				triggerArtifact( "evaluate-target.cfm" );

				var stopped = dap.waitForEvent( "stopped", 2000 );
				var threadId = stopped.body.threadId;
				var frame = getTopFrame( threadId );

				var evalResponse = dap.evaluate( frame.id, "localNum" );

				expect( evalResponse.body.result ).toBe( "100" );

				cleanupThread( threadId );
			}, skip=notSupportsEvaluate() );

			it( title="evaluates a struct key access (localStruct.key1)", body=function() {
				dap.setBreakpoints( variables.targetFile, [ lines.debugLine ] );
				triggerArtifact( "evaluate-target.cfm" );

				var stopped = dap.waitForEvent( "stopped", 2000 );
				var threadId = stopped.body.threadId;
				var frame = getTopFrame( threadId );

				var evalResponse = dap.evaluate( frame.id, "localStruct.key1" );

				expect( evalResponse.body.result ).toBe( '"value1"' );

				cleanupThread( threadId );
			}, skip=notSupportsEvaluate() );

			it( title="evaluates a nested struct key (localStruct.nested.inner)", body=function() {
				dap.setBreakpoints( variables.targetFile, [ lines.debugLine ] );
				triggerArtifact( "evaluate-target.cfm" );

				var stopped = dap.waitForEvent( "stopped", 2000 );
				var threadId = stopped.body.threadId;
				var frame = getTopFrame( threadId );

				var evalResponse = dap.evaluate( frame.id, "localStruct.nested.inner" );

				expect( evalResponse.body.result ).toBe( '"deep"' );

				cleanupThread( threadId );
			}, skip=notSupportsEvaluate() );

			it( title="evaluates an array element access (localArray[2])", body=function() {
				dap.setBreakpoints( variables.targetFile, [ lines.debugLine ] );
				triggerArtifact( "evaluate-target.cfm" );

				var stopped = dap.waitForEvent( "stopped", 2000 );
				var threadId = stopped.body.threadId;
				var frame = getTopFrame( threadId );

				var evalResponse = dap.evaluate( frame.id, "localArray[2]" );

				expect( evalResponse.body.result ).toBe( "20" );

				cleanupThread( threadId );
			}, skip=notSupportsEvaluate() );

			it( title="evaluates arguments-scope access (arguments.data.name)", body=function() {
				dap.setBreakpoints( variables.targetFile, [ lines.debugLine ] );
				triggerArtifact( "evaluate-target.cfm" );

				var stopped = dap.waitForEvent( "stopped", 2000 );
				var threadId = stopped.body.threadId;
				var frame = getTopFrame( threadId );

				var evalResponse = dap.evaluate( frame.id, "arguments.data.name" );

				expect( evalResponse.body.result ).toBe( '"test-input"' );

				cleanupThread( threadId );
			}, skip=notSupportsEvaluate() );

			it( title="evaluates a string concatenation expression", body=function() {
				dap.setBreakpoints( variables.targetFile, [ lines.debugLine ] );
				triggerArtifact( "evaluate-target.cfm" );

				var stopped = dap.waitForEvent( "stopped", 2000 );
				var threadId = stopped.body.threadId;
				var frame = getTopFrame( threadId );

				var evalResponse = dap.evaluate( frame.id, "localVar & ' - ' & dataName" );

				expect( evalResponse.body.result ).toBe( '"local-value - test-input"' );

				cleanupThread( threadId );
			}, skip=notSupportsEvaluate() );

			it( title="evaluates a math expression with variables", body=function() {
				dap.setBreakpoints( variables.targetFile, [ lines.debugLine ] );
				triggerArtifact( "evaluate-target.cfm" );

				var stopped = dap.waitForEvent( "stopped", 2000 );
				var threadId = stopped.body.threadId;
				var frame = getTopFrame( threadId );

				var evalResponse = dap.evaluate( frame.id, "localNum * 2 + 50" );

				expect( evalResponse.body.result ).toBe( "250" );

				cleanupThread( threadId );
			}, skip=notSupportsEvaluate() );

			it( title="evaluates a built-in function call (len)", body=function() {
				dap.setBreakpoints( variables.targetFile, [ lines.debugLine ] );
				triggerArtifact( "evaluate-target.cfm" );

				var stopped = dap.waitForEvent( "stopped", 2000 );
				var threadId = stopped.body.threadId;
				var frame = getTopFrame( threadId );

				var evalResponse = dap.evaluate( frame.id, "len(localVar)" );

				expect( evalResponse.body.result ).toBe( "11" ); // "local-value" = 11 chars

				cleanupThread( threadId );
			}, skip=notSupportsEvaluate() );

			it( title="evaluates arrayLen on a local array", body=function() {
				dap.setBreakpoints( variables.targetFile, [ lines.debugLine ] );
				triggerArtifact( "evaluate-target.cfm" );

				var stopped = dap.waitForEvent( "stopped", 2000 );
				var threadId = stopped.body.threadId;
				var frame = getTopFrame( threadId );

				var evalResponse = dap.evaluate( frame.id, "arrayLen(localArray)" );

				expect( evalResponse.body.result ).toBe( "3" );

				cleanupThread( threadId );
			}, skip=notSupportsEvaluate() );

		} );
	}
}
