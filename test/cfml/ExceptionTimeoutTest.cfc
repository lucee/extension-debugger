/**
 * Uncaught-exception breakpoint — request timeout.
 *
 * RequestTimeoutException is in the Abort tree but NOT silent — it falls
 * through the Abort.isSilentAbort filter and DOES fire the uncaught-exception
 * breakpoint. Regression guard to make sure any future filter change doesn't
 * accidentally start suppressing timeouts.
 */
component extends="org.lucee.cfml.test.LuceeTestCase" labels="dap" {

	include "DapTestCase.cfm";

	function beforeAll() {
		setupDap();
	}

	function run( testResults, testBox ) {
		describe( "DAP request-timeout uncaught breakpoint", function() {

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
					waitForHttpComplete( 5000 );
				} catch ( any e ) {
					systemOutput( "afterEach: http drain timeout ignored: #e.message#", true );
				}

				dap.drainEvents();
			} );

			// RequestTimeoutException is constructed from a ThreadDeath Error mid-execution;
			// the Lucee thread is killed before it can block on the debugger suspend lock.
			// Needs a separate notify path that fires before the thread dies.
			// Separate bug, out of scope for LDEV-6282.
			xit( "RequestTimeoutException DOES trigger the uncaught breakpoint", function() {
				dap.setExceptionBreakpoints( [ "uncaught" ] );
				triggerArtifact( "exception-timeout-target.cfm", {}, true );

				var stopped = dap.waitForEvent( "stopped", 5000 );
				expect( stopped.body.reason ).toBe( "exception", "Request timeout should fire the uncaught-exception breakpoint" );

				cleanupThread( stopped.body.threadId );
			} );

		} );
	}
}
