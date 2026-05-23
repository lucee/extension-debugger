/**
 * Tests for DAP getApplicationSettings custom request.
 *
 * Native mode: resolves getApplicationSettings() + serializeJSON() (via
 * reflection today, loadBIF after the refactor) and returns the JSON-serialized
 * struct of this-scope application settings.
 * Agent / JDWP mode: returns the literal JSON string
 * "getApplicationSettings not supported in JDWP mode".
 *
 * Regression guard: the native path was written with loadClass/getMethod and
 * catch-everything blocks — same shape as the dump DEFAULT_RICH bug that
 * silently returned error HTML. Strict assertions here (known this.* values
 * from artifacts/appSettings/Application.cfc) expose silent divergence
 * between the reflective call and what the BIF would return.
 *
 * BDD style — skip= uses capabilities probed at include-time via DapTestCase.cfm.
 */
component extends="org.lucee.cfml.test.LuceeTestCase" labels="dap" {

	include "DapTestCase.cfm";

	variables.targetFile = "";

	variables.lines = {
		debugLine: 5   // appSettings/index.cfm: var debugLine = "inspect here";
	};

	function beforeAll() {
		setupDap();
		variables.targetFile = getArtifactPath( "appSettings/index.cfm" );
	}

	function run( testResults, testBox ) {
		describe( "DAP getApplicationSettings", function() {

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

			it( title="native: target line is a valid breakpoint location", body=function() {
				var locations = dap.breakpointLocations( variables.targetFile, 1, 20 );
				var validLines = locations.body.breakpoints.map( function( bp ) { return bp.line; } );

				systemOutput( "#variables.targetFile# valid lines: #serializeJSON( validLines )#", true );

				for ( var key in variables.lines ) {
					var line = variables.lines[ key ];
					expect( validLines ).toInclude( line, "#variables.targetFile# line #line# (#key#) should be a valid breakpoint location" );
				}
			}, skip=notNativeMode() );

			it( "returns valid JSON with application name", function() {
				dap.setBreakpoints( variables.targetFile, [ lines.debugLine ] );
				triggerArtifact( "appSettings/index.cfm" );

				var stopped = dap.waitForEvent( "stopped", 2000 );
				var threadId = stopped.body.threadId;

				var response = dap.getApplicationSettings();

				systemOutput( "getApplicationSettings content: #response.body.content#", true );

				expect( isJSON( response.body.content ) ).toBeTrue();
				var parsed = deserializeJSON( response.body.content );

				if ( isNativeMode() ) {
					expect( parsed ).toBeTypeOf( "struct" );
					// name is set in Application.cfc as this.name = "app-settings-dap-test"
					expect( parsed ).toHaveKey( "name" );
					expect( parsed.name ).toBe( "app-settings-dap-test" );
				} else {
					// Agent / JDWP mode is a stub.
					expect( parsed ).toBe( "getApplicationSettings not supported in JDWP mode" );
				}

				// Regression guard: server still responsive after the call.
				expect( dap.threads() ).toHaveKey( "body" );

				cleanupThread( threadId );
			} );

			it( title="native: reflects known this.* settings from Application.cfc", body=function() {
				dap.setBreakpoints( variables.targetFile, [ lines.debugLine ] );
				triggerArtifact( "appSettings/index.cfm" );

				var stopped = dap.waitForEvent( "stopped", 2000 );
				var threadId = stopped.body.threadId;

				var response = dap.getApplicationSettings();
				var parsed = deserializeJSON( response.body.content );

				expect( parsed ).toBeTypeOf( "struct" );

				// Application.cfc sets these explicitly — they must round-trip.
				// A silent error in the reflective call path would leave these
				// at their framework defaults, exactly like the DEFAULT_RICH
				// dump bug.
				expect( parsed.name ).toBe( "app-settings-dap-test" );
				expect( parsed ).toHaveKey( "sessionManagement" );
				expect( parsed.sessionManagement ).toBeTrue();
				expect( parsed ).toHaveKey( "setClientCookies" );
				expect( parsed.setClientCookies ).toBeFalse();

				cleanupThread( threadId );
			}, skip=notNativeMode() );

			it( title="native: server survives getApplicationSettings before any breakpoint", body=function() {
				// With no suspended frame to pull a PageContext from, native-mode
				// returns a short JSON string describing the condition. The key
				// assertion is that the call completes and the server stays alive
				// — the prior reflection shape could have thrown
				// NoClassDefFoundError here and the catch block would have
				// produced an opaque error string.
				var response = dap.getApplicationSettings();

				expect( isJSON( response.body.content ) ).toBeTrue();

				// Server still responsive.
				expect( dap.threads() ).toHaveKey( "body" );
			}, skip=notNativeMode() );

			// Multi-thread cross-bleed: getApplicationSettings has no threadId in its
			// payload, so it relies on the active-thread tracker to pick a PC. Flaky
			// against the old getAnySuspendedPageContext() until that lands.
			it( title="multi-thread: getApplicationSettings resolves to last-interacted thread's app context, not a random suspended PC", body=function() {
				var multiTargetFile = getArtifactPath( "appSettings-multi/index.cfm" );
				var multiLines = { breakpoint: 11 };  // debugLine = "inspect here";
				dap.setBreakpoints( multiTargetFile, [ multiLines.breakpoint ] );

				var handleA = triggerArtifactBackground( "appSettings-multi/index.cfm", { appname: "app-thread-a" } );
				var handleB = triggerArtifactBackground( "appSettings-multi/index.cfm", { appname: "app-thread-b" } );

				var stopped1 = dap.waitForEvent( "stopped", 5000 );
				var stopped2 = dap.waitForEvent( "stopped", 5000 );

				var threadId1 = stopped1.body.threadId;
				var threadId2 = stopped2.body.threadId;
				expect( threadId1 ).notToBe( threadId2, "Two concurrent requests should produce distinct threadIds" );

				// Resolve which threadId owns which app context via frame-scoped eval —
				// the frame.id path is already deterministic.
				var frame1 = getTopFrame( threadId1 );
				var frame2 = getTopFrame( threadId2 );
				var name1 = dap.evaluate( frame1.id, "appName" ).body.result;
				var name2 = dap.evaluate( frame2.id, "appName" ).body.result;
				expect( name1 ).notToBe( name2, "Sanity: distinct app contexts should produce distinct appName" );

				// Interact with thread A first — getApplicationSettings must return A's app name.
				dap.stackTrace( threadId1 );
				var settingsAfterA = deserializeJSON( dap.getApplicationSettings().body.content );
				expect( '"' & settingsAfterA.name & '"' ).toBe( name1,
					"after interacting with thread #threadId1#, getApplicationSettings should "
					& "return its app name (#name1#), not bleed to thread #threadId2# (#name2#); "
					& "got '#settingsAfterA.name#'"
				);

				// Reverse — same guarantee for B.
				dap.stackTrace( threadId2 );
				var settingsAfterB = deserializeJSON( dap.getApplicationSettings().body.content );
				expect( '"' & settingsAfterB.name & '"' ).toBe( name2,
					"after interacting with thread #threadId2#, getApplicationSettings should "
					& "return its app name (#name2#), not bleed to thread #threadId1# (#name1#); "
					& "got '#settingsAfterB.name#'"
				);

				try { dap.continueThread( threadId1 ); } catch ( any e ) {}
				try { dap.continueThread( threadId2 ); } catch ( any e ) {}
				try { waitForBackgroundComplete( handleA, 5000 ); } catch ( any e ) {}
				try { waitForBackgroundComplete( handleB, 5000 ); } catch ( any e ) {}
			}, skip=notNativeMode() );

		} );
	}
}
