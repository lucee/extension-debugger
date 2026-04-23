/**
 * Uncaught-exception breakpoint — compile-error behaviour.
 *
 * Compile / parse errors reach `_doInclude` catch BEFORE any CFML frame is
 * pushed for that file. The same empty-frames filter that suppresses top-level
 * MissingIncludeException also suppresses top-level compile errors — no live
 * user frame to break on. Nested compile errors (parent page includes a broken
 * child) DO fire because the parent's frame is live when the child fails to
 * load.
 */
component extends="org.lucee.cfml.test.LuceeTestCase" labels="dap" {

	include "DapTestCase.cfm";

	function beforeAll() {
		setupDap();
	}

	function run( testResults, testBox ) {
		describe( "DAP compile-error uncaught-breakpoint behaviour", function() {

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

			it( title="top-level compile error does NOT fire the uncaught breakpoint", body=function() {
				dap.setExceptionBreakpoints( [ "uncaught" ] );
				triggerArtifact( "exception-compile-broken.cfm", {}, true );

				sleep( 2000 );
				expect( dap.hasEvent( "stopped" ) ).toBeFalse( "Top-level compile error has no live CFML frame — should not fire uncaught-bp" );

				waitForHttpComplete();
			}, skip=notSupportsExceptionBreakpoints() );

			it( title="nested compile error DOES fire the uncaught breakpoint on the wrapper frame", body=function() {
				dap.setExceptionBreakpoints( [ "uncaught" ] );
				triggerArtifact( "exception-compile-wrapper.cfm", {}, true );

				var stopped = dap.waitForEvent( "stopped", 3000 );
				expect( stopped.body.reason ).toBe( "exception" );

				var threadId = stopped.body.threadId;
				var frames = dap.stackTrace( threadId ).body.stackFrames;
				expect( frames.len() ).toBeGTE( 1, "Nested compile error should expose the wrapper frame" );

				var wrapperSeen = false;
				for ( var frame in frames ) {
					var path = replace( frame.source.path ?: "", "\", "/", "all" );
					if ( right( path, len( "exception-compile-wrapper.cfm" ) ) == "exception-compile-wrapper.cfm" ) {
						wrapperSeen = true;
						break;
					}
				}
				expect( wrapperSeen ).toBeTrue( "Stack should contain the wrapper frame that did the bad include" );

				cleanupThread( threadId );
			}, skip=notSupportsExceptionBreakpoints() );

		} );
	}
}
