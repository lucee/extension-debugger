/**
 * Uncaught-exception breakpoints — single-stop deduplication.
 *
 * Covers the cftry-interaction axis: whether the debugger fires multiple
 * `stopped` events for a single uncaught throw when the exception passes
 * through the bytecode `_setCatch` signal path AND the request-level
 * `execute()` catch at the top of the include chain.
 */
component extends="org.lucee.cfml.test.LuceeTestCase" labels="dap" {

	include "DapTestCase.cfm";

	function beforeAll() {
		setupDap();
	}

	function run( testResults, testBox ) {
		describe( "DAP exception dedup", function() {

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

			it( title="no cftry — exactly one stopped event per uncaught throw", body=function() {
				dap.setExceptionBreakpoints( [ "uncaught" ] );
				triggerArtifact( "exception-target.cfm", { throwException: true, catchException: false }, true );

				var first = dap.waitForEvent( "stopped", 2000 );
				expect( first.body.reason ).toBe( "exception" );
				var threadId = first.body.threadId;

				sleep( 500 );
				var events = dap.drainEvents();
				var extraStops = 0;
				for ( var event in events ) {
					if ( event.event == "stopped" && ( event.body.reason ?: "" ) == "exception" ) {
						extraStops++;
					}
				}
				expect( extraStops ).toBe( 0, "No-cftry uncaught throw should fire exactly one stopped event" );

				cleanupThread( threadId );
			}, skip=notSupportsExceptionBreakpoints() );

			it( title="non-matching cftry — exactly one stopped event per uncaught throw", body=function() {
				dap.setExceptionBreakpoints( [ "uncaught" ] );
				triggerArtifact( "exception-nonmatch-target.cfm", { throwException: true }, true );

				var first = dap.waitForEvent( "stopped", 2000 );
				expect( first.body.reason ).toBe( "exception" );
				var threadId = first.body.threadId;

				sleep( 500 );
				var events = dap.drainEvents();
				var extraStops = 0;
				for ( var event in events ) {
					if ( event.event == "stopped" && ( event.body.reason ?: "" ) == "exception" ) {
						extraStops++;
					}
				}
				expect( extraStops ).toBe( 0, "Throw through non-matching cftry should fire exactly one stopped event" );

				cleanupThread( threadId );
			}, skip=notSupportsExceptionBreakpoints() );

		} );
	}
}
