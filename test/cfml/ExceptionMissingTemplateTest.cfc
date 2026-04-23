/**
 * Uncaught-exception breakpoint — Application.cfc onMissingTemplate interaction.
 *
 * When Lucee handles a 404 via onMissingTemplate:
 * - clean handler (returns true, no throw) → MIE is absorbed, no uncaught-bp fires
 * - handler that throws → the throw comes from live user code and MUST fire the
 *   uncaught-bp, stopping inside the handler frame
 *
 * Pair with the top-level-404-no-handler case in ExceptionOriginsTest.cfc which
 * asserts no break when there is no onMissingTemplate.
 */
component extends="org.lucee.cfml.test.LuceeTestCase" labels="dap" {

	include "DapTestCase.cfm";

	function beforeAll() {
		setupDap();
	}

	function run( testResults, testBox ) {
		describe( "DAP onMissingTemplate uncaught-breakpoint interaction", function() {

			beforeEach( function() {
				dap.drainEvents();
			} );

			afterEach( function() {
				dap.setExceptionBreakpoints( [] );
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

			it( "onMissingTemplate that returns cleanly does NOT fire the uncaught breakpoint", function() {
				if ( !supportsExceptionBreakpoints() ) {
					systemOutput( "skipping: exception breakpoints not supported", true );
					return;
				}

				dap.setExceptionBreakpoints( [ "uncaught" ] );
				triggerArtifact( "exceptionInOnMissingTemplate/missing.cfm", { mode: "clean" } );

				sleep( 2000 );
				expect( dap.hasEvent( "stopped" ) ).toBeFalse( "Clean onMissingTemplate handler absorbs the MIE — no uncaught-bp should fire" );

				waitForHttpComplete();
			} );

			it( "onMissingTemplate that throws fires the uncaught breakpoint inside the handler", function() {
				if ( !supportsExceptionBreakpoints() ) {
					systemOutput( "skipping: exception breakpoints not supported", true );
					return;
				}

				dap.setExceptionBreakpoints( [ "uncaught" ] );
				triggerArtifact( "exceptionInOnMissingTemplate/missing.cfm", { mode: "throw" }, true );

				var stopped = dap.waitForEvent( "stopped", 3000 );
				expect( stopped.body.reason ).toBe( "exception" );

				var threadId = stopped.body.threadId;
				var frames = dap.stackTrace( threadId ).body.stackFrames;
				expect( frames.len() ).toBeGTE( 1, "throw inside onMissingTemplate should expose at least the handler frame" );
				expect( frames[ 1 ].name ).toInclude( "onMissingTemplate" );

				cleanupThread( threadId );
			} );

		} );
	}
}
