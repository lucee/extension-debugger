/**
 * Tests for DAP threads request.
 *
 * Native mode (NativeLuceeVm.getThreadListing):
 *  - Adds suspended threads first with " (suspended)" suffix on the name.
 *  - Iterates CFMLEngine → getCFMLFactories → active PageContexts via reflection
 *    to enumerate live request threads (currently reflective, soon to be direct
 *    casts mirroring FDControllerImpl). The catch block swallows all errors
 *    here, so this test establishes the behaviour contract before the rewrite.
 *  - Always adds a virtual "All CFML Threads" entry at id=1 so VSCode has a
 *    target for pause when no real thread is visible.
 *
 * Agent / JDWP mode (LuceeVm.getThreadListing): enumerates the JDWP thread map,
 * no virtual entry, no suspended suffix.
 *
 * BDD style — see GetApplicationSettingsTest for why `skip="fn"` doesn't work.
 */
component extends="org.lucee.cfml.test.LuceeTestCase" labels="dap" {

	include "DapTestCase.cfm";

	variables.targetFile = "";

	variables.lines = {
		debugLine: 35   // variables-target.cfm
	};

	function beforeAll() {
		setupDap();
		variables.targetFile = getArtifactPath( "variables-target.cfm" );
	}

	function run( testResults, testBox ) {
		describe( "DAP threads listing", function() {

			beforeEach( function() {
				dap.drainEvents();
			} );

			afterEach( function() {
				clearBreakpoints( variables.targetFile );

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

			it( "native: listing contains the virtual 'All CFML Threads' entry before any breakpoint", function() {
				if ( !isNativeMode() ) {
					systemOutput( "skipping: virtual entry is native-mode only", true );
					return;
				}

				var response = dap.threads();

				expect( response ).toHaveKey( "body" );
				expect( response.body ).toHaveKey( "threads" );
				expect( response.body.threads ).toBeArray();

				var virtualEntries = response.body.threads.filter( function( t ) {
					return t.id == 1 && t.name == "All CFML Threads";
				} );
				expect( arrayLen( virtualEntries ) ).toBe( 1, "virtual 'All CFML Threads' entry (id=1) should be present" );
			} );

			it( "native: listing includes the suspended thread and the virtual entry at a breakpoint", function() {
				if ( !isNativeMode() ) {
					systemOutput( "skipping: native-mode listing shape", true );
					return;
				}

				dap.setBreakpoints( variables.targetFile, [ lines.debugLine ] );
				triggerArtifact( "variables-target.cfm" );

				var stopped = dap.waitForEvent( "stopped", 2000 );
				var threadId = stopped.body.threadId;

				var response = dap.threads();

				systemOutput( "threads at breakpoint: #serializeJSON( response.body.threads )#", true );

				expect( response.body.threads ).toBeArray();
				expect( arrayLen( response.body.threads ) ).toBeGTE( 2, "expected virtual entry + suspended thread" );

				// Suspended thread's name gets " (suspended)" appended.
				var suspended = response.body.threads.filter( function( t ) {
					return t.name contains "(suspended)";
				} );
				expect( arrayLen( suspended ) ).toBeGTE( 1, "at least one thread should carry the '(suspended)' suffix" );

				// The suspended thread's id should match the id the `stopped` event reported.
				var matchingById = response.body.threads.filter( function( t ) {
					return t.id == threadId;
				} );
				expect( arrayLen( matchingById ) ).toBe( 1, "the thread id from the stopped event must appear in the listing" );

				// Virtual entry still present alongside the real suspended thread.
				var virtualEntries = response.body.threads.filter( function( t ) {
					return t.id == 1 && t.name == "All CFML Threads";
				} );
				expect( arrayLen( virtualEntries ) ).toBe( 1, "virtual 'All CFML Threads' entry must remain present while a real thread is suspended" );

				cleanupThread( threadId );
			} );

			it( "agent: listing contains the paused thread at a breakpoint", function() {
				if ( isNativeMode() ) {
					systemOutput( "skipping: agent-only listing shape", true );
					return;
				}

				// Agent / JDWP mode has a different shape (no virtual entry,
				// no (suspended) suffix), but the listing must still contain
				// the paused thread when stopped at a breakpoint.
				dap.setBreakpoints( variables.targetFile, [ lines.debugLine ] );
				triggerArtifact( "variables-target.cfm" );

				var stopped = dap.waitForEvent( "stopped", 2000 );
				var threadId = stopped.body.threadId;

				var response = dap.threads();

				expect( response.body.threads ).toBeArray();
				expect( arrayLen( response.body.threads ) ).toBeGTE( 1 );

				var matchingById = response.body.threads.filter( function( t ) {
					return t.id == threadId;
				} );
				expect( arrayLen( matchingById ) ).toBe( 1, "stopped thread id must appear in the JDWP-mode listing" );

				cleanupThread( threadId );
			} );

		} );
	}
}
