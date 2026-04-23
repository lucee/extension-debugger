/**
 * Uncaught-exception breakpoint — silent-abort filter.
 *
 * cfabort + cfcontent throw Abort-family exceptions that satisfy
 * Abort.isSilentAbort(pe). The uncaught-exception breakpoint MUST
 * NOT fire for these — today via the execute()-line-2855 filter,
 * future via the constructor-hook filter.
 */
component extends="org.lucee.cfml.test.LuceeTestCase" labels="dap" {

	include "DapTestCase.cfm";

	function beforeAll() {
		setupDap();
	}

	function run( testResults, testBox ) {
		describe( "DAP silent-abort filter", function() {

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

			it( "cfabort does NOT trigger the uncaught breakpoint", function() {
				if ( !supportsExceptionBreakpoints() ) {
					systemOutput( "skipping: exception breakpoints not supported", true );
					return;
				}

				dap.setExceptionBreakpoints( [ "uncaught" ] );
				triggerArtifact( "exception-silent-target.cfm", { mode: "abort" } );

				sleep( 2000 );
				expect( dap.hasEvent( "stopped" ) ).toBeFalse( "cfabort is isSilentAbort — must not fire the uncaught breakpoint" );

				waitForHttpComplete();
			} );

			it( "cfcontent file= does NOT trigger the uncaught breakpoint", function() {
				if ( !supportsExceptionBreakpoints() ) {
					systemOutput( "skipping: exception breakpoints not supported", true );
					return;
				}

				dap.setExceptionBreakpoints( [ "uncaught" ] );
				triggerArtifact( "exception-silent-target.cfm", { mode: "content" } );

				sleep( 2000 );
				expect( dap.hasEvent( "stopped" ) ).toBeFalse( "cfcontent file= throws PostContentAbort which is isSilentAbort — must not fire the uncaught breakpoint" );

				waitForHttpComplete();
			} );

		} );
	}
}
