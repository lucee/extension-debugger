// Agent-mode pending → verified breakpoint replay test. See
// agent-mode-verified-flip-replay.md.
component extends="org.lucee.cfml.test.LuceeTestCase" labels="dap" {

	include "DapTestCase.cfm";

	variables.targetFile = "";

	function beforeAll() {
		setupDap();
		variables.targetFile = getArtifactPath( "delayedVerify/target.cfm" );
	}

	function run( testResults, testBox ) {
		describe( "Delayed breakpoint verification", function() {

			beforeEach( function() {
				dap.drainEvents();
			} );

			// See TemplateIncludeTest.afterEach for order rationale.
			afterEach( function() {
				systemOutput( "afterEach: draining debug state", true );

				clearBreakpoints( variables.targetFile );

				for ( var threadId in dap.getSuspendedThreadIds() ) {
					try {
						dap.continueThread( threadId );
					} catch ( any e ) {
						systemOutput( "afterEach: continue thread #threadId# (ok if not suspended): #e.stacktrace#", true );
					}
				}

				try {
					waitForHttpComplete( 3000 );
				} catch ( any e ) {
					systemOutput( "afterEach: http drain timeout ignored: #e.stacktrace#", true );
				}

				dap.drainEvents();
			} );

			// Native verifies breakpoints immediately, so this replay path only
			// exercises the agent-mode placeholder flow. Runtime guard (not
			// BDD skip=) because skip= evaluates at spec-register time —
			// before beforeAll runs setupDap — so isNativeMode() would be
			// false there regardless of mode.
			it( "pending breakpoint verifies after first compile (agent-mode replay)", function() {
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
			} );

		} );
	}
}
