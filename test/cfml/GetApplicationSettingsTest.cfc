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
 * BDD style (describe/it + runtime isNativeMode() guards) is the only pattern
 * where the per-spec skip machinery works — see DelayedVerifyTest for the
 * rationale. xUnit `skip="fn"` evaluates the string as a truthy boolean so
 * the test always skips.
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

			it( "native: target line is a valid breakpoint location", function() {
				if ( !isNativeMode() ) {
					systemOutput( "skipping: breakpointLocations is native-only", true );
					return;
				}

				var locations = dap.breakpointLocations( variables.targetFile, 1, 20 );
				var validLines = locations.body.breakpoints.map( function( bp ) { return bp.line; } );

				systemOutput( "#variables.targetFile# valid lines: #serializeJSON( validLines )#", true );

				for ( var key in variables.lines ) {
					var line = variables.lines[ key ];
					expect( validLines ).toInclude( line, "#variables.targetFile# line #line# (#key#) should be a valid breakpoint location" );
				}
			} );

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

			it( "native: reflects known this.* settings from Application.cfc", function() {
				if ( !isNativeMode() ) {
					systemOutput( "skipping: native-only assertion", true );
					return;
				}

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
			} );

			it( "native: server survives getApplicationSettings before any breakpoint", function() {
				if ( !isNativeMode() ) {
					systemOutput( "skipping: native-only server-survival guard", true );
					return;
				}

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
			} );

		} );
	}
}
