/**
 * Tests for basic breakpoint functionality.
 *
 * BDD style — runtime guards inside each `it`.
 */
component extends="org.lucee.cfml.test.LuceeTestCase" labels="dap" {

	include "DapTestCase.cfm";

	variables.targetFile = "";

	// Line numbers in breakpoint-target.cfm — keep in sync with the file.
	variables.lines = {
		conditionalFunctionStart: 12,  // var result = 0;
		ifBlockBody: 14,               // result = arguments.value * 2;
		elseBlockBody: 16,             // result = arguments.value + 5;
		writeOutput: 24                // writeOutput( "Done: ..." );
	};

	function beforeAll() {
		setupDap();
		variables.targetFile = getArtifactPath( "breakpoint-target.cfm" );
	}

	function run( testResults, testBox ) {
		describe( "DAP breakpoints", function() {

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

			it( "native: all tracked line numbers in breakpoint-target are valid", function() {
				if ( !supportsBreakpointLocations() ) {
					systemOutput( "skipping: breakpointLocations not supported", true );
					return;
				}

				var locations = dap.breakpointLocations( variables.targetFile, 1, 30 );
				var validLines = locations.body.breakpoints.map( function( bp ) { return bp.line; } );

				systemOutput( "#variables.targetFile# valid lines: #serializeJSON( validLines )#", true );

				for ( var key in variables.lines ) {
					var line = variables.lines[ key ];
					expect( validLines ).toInclude( line, "#variables.targetFile# line #line# (#key#) should be a valid breakpoint location" );
				}
			} );

			it( "setBreakpoints returns a verified breakpoint (native) / placeholder (agent)", function() {
				// Uses the dedicated never-triggered target so agent-mode returns the
				// uncompiled-class placeholder regardless of test execution order.
				// See bp-placeholder-target.cfm header for why.
				var coldFile = getArtifactPath( "bp-placeholder-target.cfm" );
				var coldLine = 19;
				var response = dap.setBreakpoints( coldFile, [ coldLine ] );

				expect( response.body ).toHaveKey( "breakpoints" );
				expect( response.body.breakpoints ).toHaveLength( 1 );

				var bp = response.body.breakpoints[ 1 ];
				expect( bp ).toHaveKey( "id", "Breakpoint must carry an id so the IDE can correlate later `breakpoint` changed events" );
				expect( bp.line ).toBe( coldLine );

				if ( isNativeMode() ) {
					expect( bp.verified ).toBeTrue( "Native: bp verifies synchronously" );
				} else {
					// Agent mode: setBreakpoints on an uncompiled template returns a
					// placeholder (verified:false + id). Matches real IDE usage where
					// a user sets a bp before hitting the page. The verified:false →
					// verified:true flip is owned by DelayedVerifyTest.
					expect( bp.verified ).toBeFalse( "Agent: bp is placeholder until class compiles" );
				}
			} );

			it( "setBreakpoints handles multiple lines in one call", function() {
				var coldFile = getArtifactPath( "bp-placeholder-target.cfm" );
				var response = dap.setBreakpoints( coldFile, [ 19, 20, 21 ] );

				expect( response.body.breakpoints ).toHaveLength( 3 );
				var expectedVerified = isNativeMode();
				var modeMsg = isNativeMode() ? "Native: bp verifies synchronously" : "Agent: bp is placeholder until class compiles";
				for ( var bp in response.body.breakpoints ) {
					expect( bp ).toHaveKey( "id", "Every breakpoint must carry an id" );
					expect( bp.verified ).toBe( expectedVerified, modeMsg );
				}
			} );

			it( "execution stops at the breakpoint and the top frame reports the right line", function() {
				var bpResponse = dap.setBreakpoints( variables.targetFile, [ lines.conditionalFunctionStart ] );

				systemOutput( "testBreakpointHits: targetFile=#variables.targetFile#", true );
				systemOutput( "testBreakpointHits: response=#serializeJSON( bpResponse )#", true );

				expect( bpResponse.body.breakpoints ).toHaveLength( 1, "Should have 1 breakpoint" );
				// Don't assert verified here — native returns true, agent returns a
				// placeholder that flips via the `breakpoint` changed event. The
				// real assertion is the stopped event below.

				triggerArtifact( "breakpoint-target.cfm" );
				sleep( 500 );
				systemOutput( "testBreakpointHits: httpResult=#serializeJSON( variables.httpResult )#", true );
				expect( variables.httpResult ).notToHaveKey( "error" );

				var stopped = dap.waitForEvent( "stopped", 2000 );
				expect( stopped.body.reason ).toBe( "breakpoint" );

				var frame = getTopFrame( stopped.body.threadId );
				expect( frame.line ).toBe( lines.conditionalFunctionStart );

				cleanupThread( stopped.body.threadId );
			} );

			it( "clearing breakpoints returns an empty list", function() {
				dap.setBreakpoints( variables.targetFile, [ lines.conditionalFunctionStart, lines.ifBlockBody ] );
				var response = dap.setBreakpoints( variables.targetFile, [] );

				expect( response.body.breakpoints ).toHaveLength( 0 );
			} );

			it( "replacing the set of breakpoints keeps only the new lines", function() {
				dap.setBreakpoints( variables.targetFile, [ lines.conditionalFunctionStart, lines.ifBlockBody ] );
				var response = dap.setBreakpoints( variables.targetFile, [ lines.writeOutput ] );

				expect( response.body.breakpoints ).toHaveLength( 1 );
				expect( response.body.breakpoints[ 1 ].line ).toBe( lines.writeOutput );
			} );

			it( "conditional breakpoint hits when the condition is true (value > 10, called with 15)", function() {
				if ( !supportsConditionalBreakpoints() ) {
					systemOutput( "skipping: conditional breakpoints not supported", true );
					return;
				}

				dap.setBreakpoints( variables.targetFile, [ lines.ifBlockBody ], [ "arguments.value > 10" ] );

				triggerArtifact( "breakpoint-target.cfm" );
				sleep( 500 );
				systemOutput( "testConditionalBreakpointHits: httpResult=#serializeJSON( variables.httpResult )#", true );
				expect( variables.httpResult ).notToHaveKey( "error" );

				var stopped = dap.waitForEvent( "stopped", 2000 );
				expect( stopped.body.reason ).toBe( "breakpoint" );

				var frame = getTopFrame( stopped.body.threadId );
				expect( frame.line ).toBe( lines.ifBlockBody );

				cleanupThread( stopped.body.threadId );
			} );

			it( "conditional breakpoint skips when the condition is false (value > 100, called with 15)", function() {
				if ( !supportsConditionalBreakpoints() ) {
					systemOutput( "skipping: conditional breakpoints not supported", true );
					return;
				}

				dap.setBreakpoints( variables.targetFile, [ lines.ifBlockBody ], [ "arguments.value > 100" ] );

				triggerArtifact( "breakpoint-target.cfm" );
				sleep( 500 );
				systemOutput( "testConditionalBreakpointSkipsWhenFalse: httpResult=#serializeJSON( variables.httpResult )#", true );
				expect( variables.httpResult ).notToHaveKey( "error" );

				sleep( 2000 );

				var hasStoppedEvent = dap.hasEvent( "stopped" );
				expect( hasStoppedEvent ).toBeFalse( "Should not stop when condition is false" );

				waitForHttpComplete();
			} );

		} );
	}
}
