/**
 * Tests for console output streaming (systemOutput to debug console).
 * Native mode only — requires the consoleOutput attach option.
 *
 * BDD style — skip= uses capabilities probed at include-time via DapTestCase.cfm.
 */
component extends="org.lucee.cfml.test.LuceeTestCase" labels="dap" {

	include "DapTestCase.cfm";

	variables.targetFile = "";

	// Line numbers in console-output-target.cfm — keep in sync with the file.
	variables.lines = {
		debugLine: 14  // var stopHere = true;
	};

	function beforeAll() {
		// Enable consoleOutput for these tests.
		setupDap( consoleOutput = true );
		variables.targetFile = getArtifactPath( "console-output-target.cfm" );
	}

	function run( testResults, testBox ) {
		describe( "DAP console output streaming", function() {

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
				var locations = dap.breakpointLocations( variables.targetFile, 1, 25 );
				var validLines = locations.body.breakpoints.map( function( bp ) { return bp.line; } );

				systemOutput( "#variables.targetFile# valid lines: #serializeJSON( validLines )#", true );

				for ( var key in variables.lines ) {
					var line = variables.lines[ key ];
					expect( validLines ).toInclude( line, "#variables.targetFile# line #line# (#key#) should be a valid breakpoint location" );
				}
			}, skip=notSupportsBreakpointLocations() );

			it( title="native: emits an output event containing the systemOutput message", body=function() {
				dap.setBreakpoints( variables.targetFile, [ lines.debugLine ] );

				var testMessage = "test-output-#createUUID()#";
				triggerArtifact( "console-output-target.cfm", { message: testMessage } );

				var stopped = dap.waitForEvent( "stopped", 2000 );
				var threadId = stopped.body.threadId;

				// systemOutput fires before the breakpoint is hit — event should be queued.
				var events = dap.drainEvents();
				var foundOutput = false;

				for ( var event in events ) {
					if ( event.event == "output" && event.body.output contains testMessage ) {
						foundOutput = true;
						systemOutput( "Found output event: #serializeJSON( event )#", true );
						break;
					}
				}

				expect( foundOutput ).toBeTrue( "Should receive output event with test message" );

				cleanupThread( threadId );
			}, skip=notNativeMode() );

			it( title="native: output event carries category = stdout", body=function() {
				dap.setBreakpoints( variables.targetFile, [ lines.debugLine ] );

				var testMessage = "category-test-#createUUID()#";
				triggerArtifact( "console-output-target.cfm", { message: testMessage } );

				var stopped = dap.waitForEvent( "stopped", 2000 );
				var threadId = stopped.body.threadId;

				var events = dap.drainEvents();
				var outputEvent = {};

				for ( var event in events ) {
					if ( event.event == "output" && event.body.output contains testMessage ) {
						outputEvent = event;
						break;
					}
				}

				expect( outputEvent ).toHaveKey( "body" );
				expect( outputEvent.body ).toHaveKey( "category" );
				expect( outputEvent.body.category ).toBe( "stdout" );

				cleanupThread( threadId );
			}, skip=notNativeMode() );

			it( title="native: at least one output event fires per run", body=function() {
				// Target file has one systemOutput; this verifies the mechanism fires at all.
				dap.setBreakpoints( variables.targetFile, [ lines.debugLine ] );

				var testMessage = "multi-test-#createUUID()#";
				triggerArtifact( "console-output-target.cfm", { message: testMessage } );

				var stopped = dap.waitForEvent( "stopped", 2000 );
				var threadId = stopped.body.threadId;

				var events = dap.drainEvents();
				var outputCount = 0;

				for ( var event in events ) {
					if ( event.event == "output" ) {
						outputCount++;
						systemOutput( "Output event ##: #outputCount# - #event.body.output#", true );
					}
				}

				expect( outputCount ).toBeGTE( 1, "Should have at least one output event" );

				cleanupThread( threadId );
			}, skip=notNativeMode() );

		} );
	}
}
