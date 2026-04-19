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

	function beforeEach() {
		dap.drainEvents();
	}

	function afterEach() {
		systemOutput( "afterEach: draining debug state", true );

		try {
			clearBreakpoints( variables.idePath );
		} catch ( any e ) {
			systemOutput( "afterEach: clearBreakpoints ignored: #e.stacktrace#", true );
		}

		var threadList = dap.threads();
		for ( var t in threadList.body.threads ) {
			try {
				dap.continueThread( t.id );
			} catch ( any e ) {
				systemOutput( "afterEach: continue thread #t.id# (ok if not suspended): #e.stacktrace#", true );
			}
		}

		try {
			waitForHttpComplete( 3000 );
		} catch ( any e ) {
			systemOutput( "afterEach: http drain timeout ignored: #e.stacktrace#", true );
		}

		dap.drainEvents();
	}

	// Round-trip: set bp via ide-prefix path, trigger real URL, stopped
	// event must report source.path with the ide prefix (not the server path).
	function testBreakpointRoundTripsThroughIdePrefix() {
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
	}

	// Unmapped paths pass through setBreakpoints unchanged. We use a fake
	// prefix not in the transform list; the server treats it as a literal
	// path, fails to find the file, and reports verified:false.
	function testUnmappedPathPassesThrough() {
		var fakePath = "/totally/unmapped/" & variables.targetRelative;

		var bpResponse = dap.setBreakpoints( fakePath, [ variables.bpLine ] );
		expect( bpResponse.body.breakpoints ).toHaveLength( 1 );
		expect( bpResponse.body.breakpoints[ 1 ].verified ).toBeFalse(
			"Unmapped path should not resolve to any real file. Response: #serializeJSON( bpResponse )#"
		);

		// cleanup
		dap.setBreakpoints( fakePath, [] );
	}
}
