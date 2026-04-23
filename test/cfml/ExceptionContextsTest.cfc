/**
 * Uncaught-exception breakpoints — execution-context coverage.
 *
 * Holds the origin constant (cfthrow type=) and varies where the throw
 * happens: top-level .cfm, component method, closure, cfthread.
 *
 * BDD style — skip= uses capabilities probed at include-time via DapTestCase.cfm.
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

			it( title="top-level .cfm throw stops with a frame for the .cfm body", body=function() {
				dap.setExceptionBreakpoints( [ "uncaught" ] );
				triggerArtifact( "exception-toplevel-target.cfm", { throwException: true }, true );

				var stopped = dap.waitForEvent( "stopped", 2000 );
				expect( stopped.body.reason ).toBe( "exception" );
				var threadId = stopped.body.threadId;

				var frames = dap.stackTrace( threadId ).body.stackFrames;
				expect( frames.len() ).toBeGTE( 1, "Top-level throw should expose at least the .cfm include frame" );
				_expectPathEndsWith( frames[ 1 ].source.path, "exception-toplevel-target.cfm" );

				cleanupThread( threadId );
			}, skip=notSupportsExceptionBreakpoints() );

			it( title="component method throw stops with method + include frames", body=function() {
				dap.setExceptionBreakpoints( [ "uncaught" ] );
				triggerArtifact( "exception-component-target.cfm", { throwException: true }, true );

				var stopped = dap.waitForEvent( "stopped", 2000 );
				expect( stopped.body.reason ).toBe( "exception" );
				var threadId = stopped.body.threadId;

				var frames = dap.stackTrace( threadId ).body.stackFrames;
				expect( frames.len() ).toBeGTE( 2, "Method throw should expose method + include frames" );
				expect( frames[ 1 ].name ).toInclude( "throwFromMethod" );

				cleanupThread( threadId );
			}, skip=notSupportsExceptionBreakpoints() );

			it( title="closure throw stops with a frame at the closure body", body=function() {
				dap.setExceptionBreakpoints( [ "uncaught" ] );
				triggerArtifact( "exception-closure-target.cfm", { throwException: true }, true );

				var stopped = dap.waitForEvent( "stopped", 2000 );
				expect( stopped.body.reason ).toBe( "exception" );
				var threadId = stopped.body.threadId;

				var frames = dap.stackTrace( threadId ).body.stackFrames;
				expect( frames.len() ).toBeGTE( 2, "Closure throw should expose closure + include frames" );
				_expectPathEndsWith( frames[ 1 ].source.path, "exception-closure-target.cfm" );

				cleanupThread( threadId );
			}, skip=notSupportsExceptionBreakpoints() );

			// cfthread exceptions are caught internally by Lucee's thread runner and stored
			// silently in the thread struct — never surface as uncaught on the cfthread's
			// own Java thread. Needs a hook inside the cfthread runner's catch, separate
			// from the UDFImpl/include hooks. Separate bug, out of scope for LDEV-6282.
			// throwOnError=true case is covered by the test below.
			xit( "cfthread throw stops on a distinct thread", function() {
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

			it( title="cfthread join throwOnError=true re-throws in the calling thread and stops", body=function() {
				dap.setExceptionBreakpoints( [ "uncaught" ] );
				triggerArtifact( "exception-cfthread-throwonerror-target.cfm", { throwException: true }, true );

				var stopped = dap.waitForEvent( "stopped", 3000 );
				expect( stopped.body.reason ).toBe( "exception" );

				var threadId = stopped.body.threadId;
				var frames = dap.stackTrace( threadId ).body.stackFrames;
				expect( frames.len() ).toBeGTE( 1, "throwOnError join should expose at least the calling-thread frame" );

				cleanupThread( threadId );
			}, skip=notSupportsExceptionBreakpoints() );

			// Parallel arrayEach dispatches closures across a worker pool and rethrows
			// the first failing invocation on the caller. The uncaught-exception stop
			// may fire on a worker or the joined main thread — either is acceptable.
			// Test only requires that SOME thread stops with a frame pointing back at
			// the target file.
			it( title="parallel arrayEach closure throw stops with frame in the target", body=function() {
				dap.setExceptionBreakpoints( [ "uncaught" ] );
				triggerArtifact( "exception-parallel-arrayeach-target.cfm", { throwException: true }, true );

				var stopped = dap.waitForEvent( "stopped", 3000 );
				expect( stopped.body.reason ).toBe( "exception" );

				var threadId = stopped.body.threadId;
				var frames = dap.stackTrace( threadId ).body.stackFrames;
				expect( frames.len() ).toBeGTE( 1, "parallel arrayEach throw should expose at least one frame" );

				var targetSeen = false;
				for ( var frame in frames ) {
					var path = replace( frame.source.path ?: "", "\", "/", "all" );
					if ( right( path, len( "exception-parallel-arrayeach-target.cfm" ) ) == "exception-parallel-arrayeach-target.cfm" ) {
						targetSeen = true;
						break;
					}
				}
				expect( targetSeen ).toBeTrue( "Stack should contain a frame pointing at exception-parallel-arrayeach-target.cfm" );

				cleanupThread( threadId );
			}, skip=notSupportsExceptionBreakpoints() );

		} );
	}
}
