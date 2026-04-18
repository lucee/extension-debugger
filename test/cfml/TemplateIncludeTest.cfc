/**
 * Tests for breakpoints inside a template reached via cfinclude from inside
 * a UDF body. Covers lifecycle methods (onRequest, onRequestStart, onError)
 * and a plain UDF — all share the same root cause in Lucee core's
 * DebuggerExecutionLog: cfinclude updates the currently-executing
 * PageSource but does not push a debugger frame, so while a UDF is on
 * the stack the frame's file wins and breakpoints on the included file
 * never match.
 */
component extends="org.lucee.cfml.test.LuceeTestCase" labels="dap" {

	include "DapTestCase.cfm";

	// echo / throw line in each variant's target file
	variables.echoLine = 2;

	// Keep in sync with every bp path any test in this file sets.
	variables.knownBreakpointPaths = [];

	function beforeAll() {
		setupDap();
		variables.knownBreakpointPaths = [
			getArtifactPath( "includeInOnRequest/index.cfm" ),
			getArtifactPath( "includeInOnRequest/Application.cfc" ),
			getArtifactPath( "templateViaOnRequest/index.cfm" ),
			getArtifactPath( "includeInOnError/error.cfm" ),
			getArtifactPath( "udfInclude/inner.cfm" ),
			getArtifactPath( "cfmoduleFromUdf/widget.cfm" ),
			getArtifactPath( "customTagFromUdf/widget.cfm" ),
			getArtifactPath( "nestedIncludeFromUdf/deep.cfm" )
		];
	}

	function beforeEach() {
		dap.drainEvents();
	}

	// Clear bps before continuing so resumed threads can't re-hit and
	// leave fresh stopped events for the next test.
	function afterEach() {
		systemOutput( "afterEach: draining debug state", true );

		for ( var path in variables.knownBreakpointPaths ) {
			clearBreakpoints( path );
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

	// Lifecycle: onRequest REPLACES normal request handling, target page
	// only runs once (inside the cfinclude).
	function testBreakpointInIncludedPage_onRequest() {
		runIncludedBreakpointTest(
			scenario       = "onRequest",
			httpPath       = "includeInOnRequest/index.cfm",
			includedFile   = "includeInOnRequest/index.cfm",
			excludedMarker = "Application.cfc"
		);
	}

	// Lifecycle: onRequestStart runs BEFORE normal processing, so Lucee
	// renders the target page twice (once via cfinclude, once automatically
	// after onRequestStart returns). Breakpoint should still hit and
	// report the included file.
	function testBreakpointInIncludedPage_onRequestStart() {
		runIncludedBreakpointTest(
			scenario       = "onRequestStart",
			httpPath       = "templateViaOnRequest/index.cfm",
			includedFile   = "templateViaOnRequest/index.cfm",
			excludedMarker = "Application.cfc"
		);
	}

	// Lifecycle: onError fires when the requested page throws. Handler
	// cfincludes an error template. Breakpoint should hit in the error
	// template, not be lost inside Application.cfc's onError.
	function testBreakpointInIncludedPage_onError() {
		runIncludedBreakpointTest(
			scenario       = "onError",
			httpPath       = "includeInOnError/index.cfm",
			includedFile   = "includeInOnError/error.cfm",
			excludedMarker = "Application.cfc",
			allowErrors    = true
		);
	}

	// No lifecycle method involved: plain UDF defined inline whose body
	// cfincludes a separate template. Same bug, framework-independent.
	function testBreakpointInIncludedPage_plainUdf() {
		runIncludedBreakpointTest(
			scenario       = "plainUdf",
			httpPath       = "udfInclude/index.cfm",
			includedFile   = "udfInclude/inner.cfm",
			excludedMarker = "udfInclude/index.cfm"
		);
	}

	// TODO: agent-mode continueThread doesn't release HTTP when suspended
	// inside cfmodule; HTTP times out and poisons the event stream. See STATUS.md.
	function testBreakpointInIncludedPage_cfmoduleFromUdf() skip="true" {
		runIncludedBreakpointTest(
			scenario       = "cfmodule",
			httpPath       = "cfmoduleFromUdf/index.cfm",
			includedFile   = "cfmoduleFromUdf/widget.cfm",
			excludedMarker = "cfmoduleFromUdf/index.cfm"
		);
	}

	// TODO: <cf_widget/> fires widget.cfm twice (start + end modes);
	// the second stopped event survives drains and contaminates the next test.
	function testBreakpointInIncludedPage_customTagFromUdf() skip="true" {
		runIncludedBreakpointTest(
			scenario       = "customTag",
			httpPath       = "customTagFromUdf/index.cfm",
			includedFile   = "customTagFromUdf/widget.cfm",
			excludedMarker = "customTagFromUdf/index.cfm"
		);
	}

	// Nested cfinclude depth 2 — UDF → middle.cfm → deep.cfm, bp in deep.cfm.
	function testBreakpointInIncludedPage_nestedIncludeFromUdf() {
		runIncludedBreakpointTest(
			scenario       = "nestedInclude",
			httpPath       = "nestedIncludeFromUdf/index.cfm",
			includedFile   = "nestedIncludeFromUdf/deep.cfm",
			excludedMarker = "nestedIncludeFromUdf/index.cfm"
		);
	}

	// TODO: enable once Part D (debugger-frame-synthetic-include-frames.md) lands.
	function testIncludeFrameNameShowsIncludedFile() skip="true" {
		var bpPath = getArtifactPath( "udfInclude/inner.cfm" );

		triggerArtifact( "udfInclude/index.cfm" );
		waitForHttpComplete();

		var bpResponse = dap.setBreakpoints( bpPath, [ variables.echoLine ] );
		expect( bpResponse.body.breakpoints[ 1 ].verified ).toBeTrue();

		triggerArtifact( "udfInclude/index.cfm" );
		sleep( 500 );

		var stopped = dap.waitForEvent( "stopped", 3000 );
		var frame = getTopFrame( stopped.body.threadId );

		expect( frame.name ).notToBe( "??",
			"Include frame should have a meaningful name, got: #frame.name#"
		);

		cleanupThread( stopped.body.threadId );
		clearBreakpoints( bpPath );
	}

	// Regression guard for the LDEV-6274 core fix.
	// The fix swaps frame.getFile() for pci.getCurrentPageSource().getDisplayPath()
	// in DebuggerExecutionLog.start. For any line directly inside a UDF body (no
	// cfinclude yet), the two MUST resolve to the same file — else we've silently
	// broken every breakpoint in every function. This test breaks on the
	// `include template=...` line itself inside Application.cfc's onRequest,
	// before the include transitions into the target file.
	function testBreakpointInsideUdfBody_regressionGuard() {
		var appCfcPath = getArtifactPath( "includeInOnRequest/Application.cfc" );
		var includeLine = 5; // the `include template="#arguments.targetPage#";` line
		systemOutput( "regressionGuard: appCfcPath=#appCfcPath#", true );

		// Warm up so agent mode verifies the breakpoint on Application.cfc
		triggerArtifact( "includeInOnRequest/index.cfm" );
		waitForHttpComplete();

		var bpResponse = dap.setBreakpoints( appCfcPath, [ includeLine ] );
		systemOutput( "regressionGuard: setBreakpoints response=#serializeJSON( bpResponse )#", true );

		expect( bpResponse.body.breakpoints ).toHaveLength( 1 );
		expect( bpResponse.body.breakpoints[ 1 ].verified ).toBeTrue(
			"Breakpoint on Application.cfc:#includeLine# should be verified"
		);

		triggerArtifact( "includeInOnRequest/index.cfm" );
		sleep( 500 );

		var stopped = dap.waitForEvent( "stopped", 3000 );
		expect( stopped.body.reason ).toBe( "breakpoint" );

		var frame = getTopFrame( stopped.body.threadId );
		systemOutput( "regressionGuard: top frame=#serializeJSON( frame )#", true );

		var framePath = frame.source.path;
		expect( framePath ).toInclude( "Application.cfc",
			"Top frame should be Application.cfc when stopped on its own include line. Got: #framePath#"
		);
		expect( frame.line ).toBe( includeLine,
			"Top frame line should be #includeLine# (the include line), got #frame.line#"
		);

		cleanupThread( stopped.body.threadId );
		clearBreakpoints( appCfcPath );
	}

	// Step-over across a cfincluded file. Breakpoint stops on line 2 of the
	// included inner.cfm; step over should land on the next executable line of
	// the same included file (line 3). Guards against the fix breaking stepping
	// semantics across the cfinclude boundary — different DAP interaction, same
	// code path in DebuggerExecutionLog.start.
	function testStepOverInsideIncludedFile() {
		var innerPath = getArtifactPath( "udfInclude/inner.cfm" );
		var firstEchoLine = 2;
		var secondEchoLine = 3;
		systemOutput( "stepOver: innerPath=#innerPath#", true );

		// Warm up so inner.cfm is compiled
		triggerArtifact( "udfInclude/index.cfm" );
		waitForHttpComplete();

		var bpResponse = dap.setBreakpoints( innerPath, [ firstEchoLine ] );
		expect( bpResponse.body.breakpoints[ 1 ].verified ).toBeTrue(
			"Breakpoint on inner.cfm:#firstEchoLine# should be verified"
		);

		triggerArtifact( "udfInclude/index.cfm" );
		sleep( 500 );

		var stopped = dap.waitForEvent( "stopped", 3000 );
		expect( stopped.body.reason ).toBe( "breakpoint" );

		var threadId = stopped.body.threadId;
		var frame = getTopFrame( threadId );
		expect( frame.line ).toBe( firstEchoLine, "Should stop at inner.cfm:#firstEchoLine#" );
		expect( frame.source.path ).toInclude( "inner.cfm",
			"Initial stop should be in inner.cfm. Got: #frame.source.path#"
		);

		dap.stepOver( threadId );
		stopped = dap.waitForEvent( "stopped", 3000 );

		frame = getTopFrame( threadId );
		systemOutput( "stepOver: after-step top frame=#serializeJSON( frame )#", true );

		expect( frame.line ).toBe( secondEchoLine,
			"Step over should land on inner.cfm:#secondEchoLine#, got line #frame.line#"
		);
		expect( frame.source.path ).toInclude( "inner.cfm",
			"After step over, should still be in inner.cfm. Got: #frame.source.path#"
		);

		cleanupThread( threadId );
		clearBreakpoints( innerPath );
	}

	// ========== Helpers ==========

	private function runIncludedBreakpointTest(
		required string scenario,
		required string httpPath,
		required string includedFile,
		required string excludedMarker,
		boolean allowErrors = false
	) {
		var bpPath = getArtifactPath( arguments.includedFile );
		systemOutput( "#arguments.scenario#: bpPath=#bpPath#", true );

		// Agent mode can only verify a breakpoint on a template once its
		// class has been compiled. The included file isn't compiled until
		// it's first run via cfinclude, so warm it up with a throwaway
		// request before setting the breakpoint.
		triggerArtifact( arguments.httpPath, {}, arguments.allowErrors );
		waitForHttpComplete();

		var bpResponse = dap.setBreakpoints( bpPath, [ variables.echoLine ] );
		systemOutput( "#arguments.scenario#: setBreakpoints response=#serializeJSON( bpResponse )#", true );

		expect( bpResponse.body.breakpoints ).toHaveLength( 1 );
		expect( bpResponse.body.breakpoints[ 1 ].verified ).toBeTrue(
			"#arguments.scenario#: breakpoint on #arguments.includedFile#:#variables.echoLine# should be verified"
		);

		triggerArtifact( arguments.httpPath, {}, arguments.allowErrors );
		sleep( 500 );

		var stopped = dap.waitForEvent( "stopped", 3000 );
		expect( stopped.body.reason ).toBe( "breakpoint" );

		var frame = getTopFrame( stopped.body.threadId );
		systemOutput( "#arguments.scenario#: top frame=#serializeJSON( frame )#", true );

		var framePath = frame.source.path;
		expect( framePath ).toInclude( arguments.includedFile,
			"#arguments.scenario#: top frame should be #arguments.includedFile#. Got: #framePath#"
		);
		expect( framePath ).notToInclude( arguments.excludedMarker,
			"#arguments.scenario#: top frame should NOT be #arguments.excludedMarker#. Got: #framePath#"
		);
		expect( frame.line ).toBe( variables.echoLine,
			"#arguments.scenario#: top frame line should be #variables.echoLine#, got #frame.line#"
		);

		cleanupThread( stopped.body.threadId );
		clearBreakpoints( bpPath );
	}

}
