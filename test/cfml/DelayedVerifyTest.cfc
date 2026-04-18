// Agent-mode pending → verified breakpoint replay test. See
// agent-mode-verified-flip-replay.md.
component extends="org.lucee.cfml.test.LuceeTestCase" labels="dap" {

	include "DapTestCase.cfm";

	variables.targetFile = "";

	function beforeAll() {
		setupDap();
		variables.targetFile = getArtifactPath( "delayedVerify/target.cfm" );
	}

	function beforeEach() {
		dap.drainEvents();
	}

	// See TemplateIncludeTest.afterEach for order rationale.
	function afterEach() {
		systemOutput( "afterEach: draining debug state", true );

		clearBreakpoints( variables.targetFile );

		var threadList = dap.threads();
		for ( var t in threadList.body.threads ) {
			try {
				dap.continueThread( t.id );
			} catch ( any e ) {
				systemOutput( "afterEach: continue thread #t.id# (ok if not suspended): #e.stacktrace#", true );
			}
		}

		try {
			waitForHttpComplete( 3000 );
		} catch ( any e ) {
			systemOutput( "afterEach: http drain timeout ignored: #e.stacktrace#", true );
		}

		dap.drainEvents();
	}

	// Agent-mode only: native verifies bps immediately; this replay path
	// is agent-specific. skip="skipOnNative" attribute didn't fire in
	// TestBox (cause not diagnosed) — runtime guard instead.
	function testPendingBreakpointVerifiesAfterFirstCompile() {
		if ( isNativeMode() ) {
			systemOutput( "delayedVerify: native verifies immediately — skipping agent-replay test", true );
			return;
		}

		var bpLine = 2;

		dap.drainEvents();

		var bpResponse = dap.setBreakpoints( variables.targetFile, [ bpLine ] );
		systemOutput( "delayedVerify: initial bpResponse=#serializeJSON( bpResponse )#", true );

		expect( bpResponse.body.breakpoints ).toHaveLength( 1 );
		var placeholder = bpResponse.body.breakpoints[ 1 ];
		expect( placeholder.verified ).toBeFalse(
			"Agent mode should return verified:false for an uncompiled template. Got: #placeholder.verified#"
		);
		expect( placeholder ).toHaveKey( "id",
			"Placeholder must carry an id to correlate with the later changed event"
		);
		var bpId = placeholder.id;

		triggerArtifact( "delayedVerify/target.cfm" );
		var changed = dap.waitForEvent( "breakpoint", 5000 );
		systemOutput( "delayedVerify: changed event=#serializeJSON( changed )#", true );

		expect( changed.body.reason ).toBe( "changed",
			"Post-compile event must be reason='changed', got: #changed.body.reason#"
		);
		expect( changed.body.breakpoint.verified ).toBeTrue(
			"After compile + rebindBreakpoints, breakpoint must be verified:true"
		);
		expect( changed.body.breakpoint.id ).toBe( bpId,
			"Replayed breakpoint id #changed.body.breakpoint.id# must match original placeholder id #bpId# — otherwise the IDE can't flip the marker"
		);

		var stopped = dap.waitForEvent( "stopped", 3000 );
		expect( stopped.body.reason ).toBe( "breakpoint" );

		cleanupThread( stopped.body.threadId );
	}
}
