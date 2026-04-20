/**
 * Tests for basic breakpoint functionality.
 */
component extends="org.lucee.cfml.test.LuceeTestCase" labels="dap" {

	include "DapTestCase.cfm";

	variables.targetFile = "";

	// Line numbers in breakpoint-target.cfm - keep in sync with the file
	// These are validated in testValidateLineNumbers() using breakpointLocations (native mode only)
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

	// Validate our line number assumptions using breakpointLocations (native mode only)
	function testValidateLineNumbers_breakpointTarget() skip="notSupportsBreakpointLocations" {
		var locations = dap.breakpointLocations( variables.targetFile, 1, 30 );
		var validLines = locations.body.breakpoints.map( function( bp ) { return bp.line; } );

		systemOutput( "#variables.targetFile# valid lines: #serializeJSON( validLines )#", true );

		for ( var key in variables.lines ) {
			var line = variables.lines[ key ];
			expect( validLines ).toInclude( line, "#variables.targetFile# line #line# (#key#) should be a valid breakpoint location" );
		}
	}

	function afterEach() {
		clearBreakpoints( variables.targetFile );
	}

	// ========== Basic Breakpoints ==========

	function testSetBreakpointReturnsVerified() {
		// Use the dedicated never-triggered target so agent-mode returns the
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
			// a user sets a bp before hitting the page.
			//
			// The verified:false → verified:true flip (via `breakpoint` changed
			// event after compile) is owned end-to-end by
			// DelayedVerifyTest.testPendingBreakpointVerifiesAfterFirstCompile.
			expect( bp.verified ).toBeFalse( "Agent: bp is placeholder until class compiles" );
		}
	}

	function testSetMultipleBreakpoints() {
		// Uses the dedicated cold target — see testSetBreakpointReturnsVerified
		// for rationale. Lines don't need to correspond to real executable
		// lines in the file; agent mode's placeholder doesn't validate line
		// against an uncompiled class, native mode's breakpointLocations
		// validation runs against a different target in a different test.
		var coldFile = getArtifactPath( "bp-placeholder-target.cfm" );
		var response = dap.setBreakpoints( coldFile, [ 19, 20, 21 ] );

		expect( response.body.breakpoints ).toHaveLength( 3 );
		var expectedVerified = isNativeMode();
		var modeMsg = isNativeMode() ? "Native: bp verifies synchronously" : "Agent: bp is placeholder until class compiles";
		for ( var bp in response.body.breakpoints ) {
			expect( bp ).toHaveKey( "id", "Every breakpoint must carry an id" );
			expect( bp.verified ).toBe( expectedVerified, modeMsg );
		}
	}

	function testBreakpointHits() {
		var bpResponse = dap.setBreakpoints( variables.targetFile, [ lines.conditionalFunctionStart ] );

		systemOutput( "testBreakpointHits: targetFile=#variables.targetFile#", true );
		systemOutput( "testBreakpointHits: response=#serializeJSON( bpResponse )#", true );

		expect( bpResponse.body.breakpoints ).toHaveLength( 1, "Should have 1 breakpoint" );
		// Don't assert verified here — native returns true, agent returns a
		// placeholder that flips via the `breakpoint` changed event. The
		// real assertion is the stopped event below; if the bp wasn't
		// bound by the time execution hit the line, the event wouldn't fire.

		triggerArtifact( "breakpoint-target.cfm" );
		sleep( 500 );
		systemOutput( "testBreakpointHits: httpResult=#serializeJSON( variables.httpResult )#", true );
		expect( variables.httpResult ).notToHaveKey( "error" );

		var stopped = dap.waitForEvent( "stopped", 2000 );

		expect( stopped.body.reason ).toBe( "breakpoint" );

		var frame = getTopFrame( stopped.body.threadId );
		expect( frame.line ).toBe( lines.conditionalFunctionStart );

		cleanupThread( stopped.body.threadId );
	}

	function testClearBreakpoints() {
		dap.setBreakpoints( variables.targetFile, [ lines.conditionalFunctionStart, lines.ifBlockBody ] );

		var response = dap.setBreakpoints( variables.targetFile, [] );

		expect( response.body.breakpoints ).toHaveLength( 0 );
	}

	function testReplaceBreakpoints() {
		dap.setBreakpoints( variables.targetFile, [ lines.conditionalFunctionStart, lines.ifBlockBody ] );

		var response = dap.setBreakpoints( variables.targetFile, [ lines.writeOutput ] );

		expect( response.body.breakpoints ).toHaveLength( 1 );
		expect( response.body.breakpoints[ 1 ].line ).toBe( lines.writeOutput );
	}

	// ========== Conditional Breakpoints ==========

	function testConditionalBreakpointHits() skip="notSupportsConditionalBreakpoints" {
		// Set conditional breakpoint on if block - only hit when value > 10
		dap.setBreakpoints( variables.targetFile, [ lines.ifBlockBody ], [ "arguments.value > 10" ] );

		// Trigger - conditionalFunction is called with 15
		triggerArtifact( "breakpoint-target.cfm" );
		sleep( 500 );
		systemOutput( "testConditionalBreakpointHits: httpResult=#serializeJSON( variables.httpResult )#", true );
		expect( variables.httpResult ).notToHaveKey( "error" );

		// Should hit because 15 > 10
		var stopped = dap.waitForEvent( "stopped", 2000 );

		expect( stopped.body.reason ).toBe( "breakpoint" );

		var frame = getTopFrame( stopped.body.threadId );
		expect( frame.line ).toBe( lines.ifBlockBody );

		cleanupThread( stopped.body.threadId );
	}

	function testConditionalBreakpointSkipsWhenFalse() skip="notSupportsConditionalBreakpoints" {
		// Set conditional breakpoint that should NOT hit
		dap.setBreakpoints( variables.targetFile, [ lines.ifBlockBody ], [ "arguments.value > 100" ] );

		// Trigger - conditionalFunction is called with 15
		triggerArtifact( "breakpoint-target.cfm" );
		sleep( 500 );
		systemOutput( "testConditionalBreakpointSkipsWhenFalse: httpResult=#serializeJSON( variables.httpResult )#", true );
		expect( variables.httpResult ).notToHaveKey( "error" );

		// Should NOT hit because 15 is not > 100
		sleep( 2000 );

		var hasStoppedEvent = dap.hasEvent( "stopped" );
		expect( hasStoppedEvent ).toBeFalse( "Should not stop when condition is false" );

		waitForHttpComplete();
	}

}
