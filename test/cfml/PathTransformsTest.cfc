// pathTransforms round-trip: IDE-side paths come in via setBreakpoints,
// server rewrites them to real paths; stopped events rewrite the real
// path back to the IDE-side prefix so the client matches its marker.
component extends="org.lucee.cfml.test.LuceeTestCase" labels="dap" {

	include "DapTestCase.cfm";

	variables.idePrefix = "/ide/fake/";
	variables.unmappedIdePrefix = "/ide/other/";
	variables.targetRelative = "pathTransforms/target.cfm";
	variables.bpLine = 2;
	variables.idePath = "";
	variables.serverPath = "";

	function beforeAll() {
		// Need the real server-side artifact root up-front to build the
		// serverPrefix mapping. setupDap populates debuggeeArtifactPath via
		// include-time init; call it before reading.
		var envArtifactPath = server.system.environment.DEBUGGEE_ARTIFACT_PATH ?: "";
		if ( !len( envArtifactPath ) ) {
			throw( type="PathTransformsTest.ConfigError",
				message="DEBUGGEE_ARTIFACT_PATH env var required — this test only runs in the CI debuggee topology" );
		}

		setupDap( pathTransforms = [
			{ "idePrefix": variables.idePrefix, "serverPrefix": envArtifactPath },
			{ "idePrefix": "/alt/unused/",       "serverPrefix": "/nowhere/real/" }
		] );

		variables.idePath = variables.idePrefix & variables.targetRelative;
		variables.serverPath = getArtifactPath( variables.targetRelative );
	}

	function run( testResults, testBox ) {
		describe( "DAP pathTransforms (ide ↔ server prefix rewriting)", function() {

			beforeEach( function() {
				dap.drainEvents();
			} );

			afterEach( function() {
				systemOutput( "afterEach: draining debug state", true );

				try {
					clearBreakpoints( variables.idePath );
				} catch ( any e ) {
					systemOutput( "afterEach: clearBreakpoints ignored: #e.stacktrace#", true );
				}

				for ( var threadId in dap.getSuspendedThreadIds() ) {
					try {
						dap.continueThread( threadId );
					} catch ( any e ) {
						systemOutput( "afterEach: continue thread #threadId# (ok if not suspended): #e.stacktrace#", true );
					}
				}

				try {
					waitForHttpComplete( 3000 );
				} catch ( any e ) {
					systemOutput( "afterEach: http drain timeout ignored: #e.stacktrace#", true );
				}

				dap.drainEvents();
			} );

			// Round-trip: set bp via ide-prefix path, trigger real URL, stopped
			// event must report source.path with the ide prefix (not the server path).
			it( "round-trips a breakpoint set on an ide-prefix path", function() {
				systemOutput( "pathTransforms: idePath=#variables.idePath# serverPath=#variables.serverPath#", true );

				triggerArtifact( variables.targetRelative );
				waitForHttpComplete();

				var bpResponse = dap.setBreakpoints( variables.idePath, [ variables.bpLine ] );
				expect( bpResponse.body.breakpoints ).toHaveLength( 1 );
				expect( bpResponse.body.breakpoints[ 1 ].verified ).toBeTrue(
					"Breakpoint on ide-prefix path #variables.idePath# should resolve + verify. Response: #serializeJSON( bpResponse )#"
				);

				triggerArtifact( variables.targetRelative );
				sleep( 500 );

				var stopped = dap.waitForEvent( "stopped", 3000 );
				expect( stopped.body.reason ).toBe( "breakpoint" );

				var frame = getTopFrame( stopped.body.threadId );
				systemOutput( "pathTransforms: top frame=#serializeJSON( frame )#", true );

				expect( frame.source.path contains variables.idePrefix ).toBeTrue(
					"Stopped event source.path should contain ide prefix '#variables.idePrefix#', got: #frame.source.path#"
				);
				expect( frame.source.path contains variables.serverPath ).toBeFalse(
					"Server-side path should have been rewritten out. Got: #frame.source.path#"
				);

				cleanupThread( stopped.body.threadId );
			} );

			// Unmapped paths pass through setBreakpoints unchanged. We use a fake
			// prefix not in the transform list; the server treats it as a literal
			// path, fails to find the file, and reports verified:false.
			//
			// setBreakpoints response doesn't echo source.path back (see DapServer
			// map_cfBreakpoint_to_lsp4jBreakpoint — only id/line/verified), so we
			// can't assert "path was not transformed" directly. Positive control
			// instead: the same relative file under the REAL ide prefix verifies
			// successfully on the same test call. That proves the only reason the
			// fake-prefix call fails is the missing transform entry, not a path-
			// resolution problem with the target file itself.
			it( "leaves an unmapped path unchanged (positive control proves the file exists)", function() {
				var fakePath = "/totally/unmapped/" & variables.targetRelative;

				triggerArtifact( variables.targetRelative );
				waitForHttpComplete();

				// Negative: fake prefix — no transform, file not found under literal path
				var unmappedResponse = dap.setBreakpoints( fakePath, [ variables.bpLine ] );
				expect( unmappedResponse.body.breakpoints ).toHaveLength( 1 );
				expect( unmappedResponse.body.breakpoints[ 1 ].verified ).toBeFalse(
					"Unmapped path should not resolve. Response: #serializeJSON( unmappedResponse )#"
				);

				// Positive control: same relative file, real ide prefix — MUST verify.
				// If this also returns false, something other than the missing transform
				// is wrong and the negative assertion above was meaningless.
				var mappedResponse = dap.setBreakpoints( variables.idePath, [ variables.bpLine ] );
				expect( mappedResponse.body.breakpoints[ 1 ].verified ).toBeTrue(
					"Positive control: same file under real prefix #variables.idePrefix# should verify. Response: #serializeJSON( mappedResponse )#"
				);

				// cleanup both paths
				dap.setBreakpoints( fakePath, [] );
				dap.setBreakpoints( variables.idePath, [] );
			} );

		} );
	}
}
