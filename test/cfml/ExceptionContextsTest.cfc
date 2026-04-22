/**
 * Uncaught-exception breakpoints — execution-context coverage.
 *
 * Holds the origin constant (cfthrow type=) and varies where the throw
 * happens: top-level .cfm, component method, closure, cfthread.
 */
component extends="org.lucee.cfml.test.LuceeTestCase" labels="dap" {

	include "DapTestCase.cfm";

	function beforeAll() {
		setupDap();
	}

	function run( testResults, testBox ) {
		describe( "DAP exception contexts", function() {

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

			it( "top-level .cfm throw stops with a frame for the .cfm body", function() {
				if ( !supportsExceptionBreakpoints() ) {
					systemOutput( "skipping: exception breakpoints not supported", true );
					return;
				}

				dap.setExceptionBreakpoints( [ "uncaught" ] );
				triggerArtifact( "exception-toplevel-target.cfm", { throwException: true }, true );

				var stopped = dap.waitForEvent( "stopped", 2000 );
				expect( stopped.body.reason ).toBe( "exception" );
				var threadId = stopped.body.threadId;

				var frames = dap.stackTrace( threadId ).body.stackFrames;
				expect( frames.len() ).toBeGTE( 1, "Top-level throw should expose at least the .cfm include frame" );
				_expectPathEndsWith( frames[ 1 ].source.path, "exception-toplevel-target.cfm" );

				cleanupThread( threadId );
			} );

			it( "component method throw stops with method + include frames", function() {
				if ( !supportsExceptionBreakpoints() ) {
					systemOutput( "skipping: exception breakpoints not supported", true );
					return;
				}

				dap.setExceptionBreakpoints( [ "uncaught" ] );
				triggerArtifact( "exception-component-target.cfm", { throwException: true }, true );

				var stopped = dap.waitForEvent( "stopped", 2000 );
				expect( stopped.body.reason ).toBe( "exception" );
				var threadId = stopped.body.threadId;

				var frames = dap.stackTrace( threadId ).body.stackFrames;
				expect( frames.len() ).toBeGTE( 2, "Method throw should expose method + include frames" );
				expect( frames[ 1 ].name ).toInclude( "throwFromMethod" );

				cleanupThread( threadId );
			} );

			it( "closure throw stops with a frame at the closure body", function() {
				if ( !supportsExceptionBreakpoints() ) {
					systemOutput( "skipping: exception breakpoints not supported", true );
					return;
				}

				dap.setExceptionBreakpoints( [ "uncaught" ] );
				triggerArtifact( "exception-closure-target.cfm", { throwException: true }, true );

				var stopped = dap.waitForEvent( "stopped", 2000 );
				expect( stopped.body.reason ).toBe( "exception" );
				var threadId = stopped.body.threadId;

				var frames = dap.stackTrace( threadId ).body.stackFrames;
				expect( frames.len() ).toBeGTE( 2, "Closure throw should expose closure + include frames" );
				_expectPathEndsWith( frames[ 1 ].source.path, "exception-closure-target.cfm" );

				cleanupThread( threadId );
			} );

			it( "cfthread throw stops on a distinct thread", function() {
				if ( !supportsExceptionBreakpoints() ) {
					systemOutput( "skipping: exception breakpoints not supported", true );
					return;
				}

				dap.setExceptionBreakpoints( [ "uncaught" ] );
				triggerArtifact( "exception-cfthread-target.cfm", { throwException: true } );

				var stopped = dap.waitForEvent( "stopped", 3000 );
				expect( stopped.body.reason ).toBe( "exception" );

				var threadId = stopped.body.threadId;
				var frames = dap.stackTrace( threadId ).body.stackFrames;
				expect( frames.len() ).toBeGTE( 1, "cfthread throw should expose at least one frame" );
				_expectPathEndsWith( frames[ 1 ].source.path, "exception-cfthread-target.cfm" );

				cleanupThread( threadId );
			} );

		} );
	}
}
