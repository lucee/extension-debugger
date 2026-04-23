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
			getArtifactPath( "customTagDoubleFireFromUdf/widget.cfm" ),
			getArtifactPath( "nestedIncludeFromUdf/deep.cfm" )
		];
	}

	function run( testResults, testBox ) {
		describe( "Breakpoint in template cfincluded from a UDF", function() {

			beforeEach( function() {
				dap.drainEvents();
			} );

			// Clear bps before continuing so resumed threads can't re-hit and
			// leave fresh stopped events for the next test.
			afterEach( function() {
				systemOutput( "afterEach: draining debug state", true );

				for ( var path in variables.knownBreakpointPaths ) {
					clearBreakpoints( path );
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

			describe( "Lifecycle methods", function() {

				// onRequest REPLACES normal request handling, target page only
				// runs once (inside the cfinclude).
				it( "fires breakpoint inside page cfincluded from onRequest", function() {
					runIncludedBreakpointTest(
						scenario     = "onRequest",
						httpPath     = "includeInOnRequest/index.cfm",
						includedFile = "includeInOnRequest/index.cfm"
					);
				} );

				// onRequestStart runs BEFORE normal processing, so Lucee renders
				// the target page twice (once via cfinclude, once automatically
				// after onRequestStart returns). Breakpoint should still hit and
				// report the included file.
				it( "fires breakpoint inside page cfincluded from onRequestStart", function() {
					runIncludedBreakpointTest(
						scenario     = "onRequestStart",
						httpPath     = "templateViaOnRequest/index.cfm",
						includedFile = "templateViaOnRequest/index.cfm"
					);
				} );

				// onError fires when the requested page throws. Handler cfincludes
				// an error template. Breakpoint should hit in the error template,
				// not be lost inside Application.cfc's onError.
				it( "fires breakpoint inside error template cfincluded from onError", function() {
					runIncludedBreakpointTest(
						scenario     = "onError",
						httpPath     = "includeInOnError/index.cfm",
						includedFile = "includeInOnError/error.cfm",
						allowErrors  = true
					);
				} );
			} );

			describe( "Non-lifecycle UDF paths", function() {

				// No lifecycle method involved: plain UDF defined inline whose
				// body cfincludes a separate template. Same bug, framework-free.
				it( "fires breakpoint inside page cfincluded from a plain UDF", function() {
					runIncludedBreakpointTest(
						scenario     = "plainUdf",
						httpPath     = "udfInclude/index.cfm",
						includedFile = "udfInclude/inner.cfm"
					);
				} );

				// cfmodule dispatches widget.cfm as a custom tag (runs twice:
				// start + end). Artifact guards with `exit "exitTag"` in end
				// mode so bp fires once; echo shifts to line 3.
				it( "fires breakpoint inside widget cfmodule'd from a UDF", function() {
					runIncludedBreakpointTest(
						scenario     = "cfmodule",
						httpPath     = "cfmoduleFromUdf/index.cfm",
						includedFile = "cfmoduleFromUdf/widget.cfm",
						bpLine       = 3
					);
				} );

				// Custom tag from UDF — same execution-mode guard as cfmodule.
				it( "fires breakpoint inside custom tag invoked from a UDF", function() {
					runIncludedBreakpointTest(
						scenario     = "customTag",
						httpPath     = "customTagFromUdf/index.cfm",
						includedFile = "customTagFromUdf/widget.cfm",
						bpLine       = 3
					);
				} );

				// Nested cfinclude depth 2 — UDF → middle.cfm → deep.cfm, bp in deep.cfm.
				it( "fires breakpoint inside deeply nested cfinclude (depth 2) from a UDF", function() {
					runIncludedBreakpointTest(
						scenario     = "nestedInclude",
						httpPath     = "nestedIncludeFromUdf/index.cfm",
						includedFile = "nestedIncludeFromUdf/deep.cfm"
					);
				} );
			} );

			describe( "Custom tag execution-mode semantics", function() {

				// Unguarded custom tag so widget.cfm runs in BOTH start and end
				// modes. Proves the debugger handles a single bp firing twice on
				// the same thread across consecutive custom-tag execution modes.
				it( "fires breakpoint in both start and end execution modes on same thread", function() {
					var bpPath = getArtifactPath( "customTagDoubleFireFromUdf/widget.cfm" );
					systemOutput( "customTagDoubleFire: bpPath=#bpPath#", true );

					triggerArtifact( "customTagDoubleFireFromUdf/index.cfm" );
					waitForHttpComplete();

					var bpResponse = dap.setBreakpoints( bpPath, [ variables.echoLine ] );
					expect( bpResponse.body.breakpoints[ 1 ].verified ).toBeTrue();

					triggerArtifact( "customTagDoubleFireFromUdf/index.cfm" );
					sleep( 500 );

					// First fire — start mode
					var firstStop = dap.waitForEvent( "stopped", 3000 );
					expect( firstStop.body.reason ).toBe( "breakpoint" );
					var firstFrame = getTopFrame( firstStop.body.threadId );
					_expectPathEndsWith( firstFrame.source.path, "customTagDoubleFireFromUdf/widget.cfm" );
					expect( firstFrame.line ).toBe( variables.echoLine );

					dap.continueThread( firstStop.body.threadId );

					// Second fire — end mode, same thread
					var secondStop = dap.waitForEvent( "stopped", 3000 );
					expect( secondStop.body.reason ).toBe( "breakpoint" );
					expect( secondStop.body.threadId ).toBe( firstStop.body.threadId,
						"Second fire should be on same thread. Got #secondStop.body.threadId#, expected #firstStop.body.threadId#"
					);
					var secondFrame = getTopFrame( secondStop.body.threadId );
					_expectPathEndsWith( secondFrame.source.path, "customTagDoubleFireFromUdf/widget.cfm" );
					expect( secondFrame.line ).toBe( variables.echoLine );

					cleanupThread( secondStop.body.threadId );
					clearBreakpoints( bpPath );
				} );
			} );

			describe( "Frame metadata (native mode)", function() {

				it( title="include frame name is the included file's basename", body=function() {
					var bpPath = getArtifactPath( "udfInclude/inner.cfm" );

					triggerArtifact( "udfInclude/index.cfm" );
					waitForHttpComplete();

					var bpResponse = dap.setBreakpoints( bpPath, [ variables.echoLine ] );
					expect( bpResponse.body.breakpoints[ 1 ].verified ).toBeTrue();

					triggerArtifact( "udfInclude/index.cfm" );
					sleep( 500 );

					var stopped = dap.waitForEvent( "stopped", 3000 );
					var frame = getTopFrame( stopped.body.threadId );

					expect( frame.name ).toBe( "inner.cfm",
						"Include frame name should be the included file's basename. Got: '#frame.name#'"
					);

					cleanupThread( stopped.body.threadId );
					clearBreakpoints( bpPath );
				}, skip=notNativeMode() );
			} );

			describe( "Regression guards for the core fix", function() {

				// The core fix swaps frame.getFile() for
				// pci.getCurrentPageSource().getDisplayPath() in
				// DebuggerExecutionLog.start. For any line directly inside a UDF
				// body (no cfinclude yet), the two MUST resolve to the same file —
				// else we've silently broken every breakpoint in every function.
				// This spec breaks on the `include template=...` line itself
				// inside Application.cfc's onRequest, before the include
				// transitions into the target file.
				it( "breakpoint on the UDF's own include line still reports the UDF's file", function() {
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

					_expectPathEndsWith( frame.source.path, "includeInOnRequest/Application.cfc",
						"Top frame should be Application.cfc when stopped on its own include line. Got: #frame.source.path#"
					);
					expect( frame.line ).toBe( includeLine,
						"Top frame line should be #includeLine# (the include line), got #frame.line#"
					);

					cleanupThread( stopped.body.threadId );
					clearBreakpoints( appCfcPath );
				} );

				// Step-over across a cfincluded file. Breakpoint stops on line 2
				// of the included inner.cfm; step over should land on the next
				// executable line of the same included file (line 3). Guards
				// against the fix breaking stepping semantics across the
				// cfinclude boundary — different DAP interaction, same code path
				// in DebuggerExecutionLog.start.
				it( "step-over stays inside the cfincluded file", function() {
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
					_expectPathEndsWith( frame.source.path, "udfInclude/inner.cfm",
						"Initial stop should be in inner.cfm. Got: #frame.source.path#"
					);

					dap.stepOver( threadId );
					stopped = dap.waitForEvent( "stopped", 3000 );

					frame = getTopFrame( threadId );
					systemOutput( "stepOver: after-step top frame=#serializeJSON( frame )#", true );

					expect( frame.line ).toBe( secondEchoLine,
						"Step over should land on inner.cfm:#secondEchoLine#, got line #frame.line#"
					);
					_expectPathEndsWith( frame.source.path, "udfInclude/inner.cfm",
						"After step over, should still be in inner.cfm. Got: #frame.source.path#"
					);

					cleanupThread( threadId );
					clearBreakpoints( innerPath );
				} );
			} );

		} );
	}

	// ========== Helpers ==========

	private function runIncludedBreakpointTest(
		required string scenario,
		required string httpPath,
		required string includedFile,
		boolean allowErrors = false,
		numeric bpLine = variables.echoLine
	) {
		var bpPath = getArtifactPath( arguments.includedFile );
		systemOutput( "#arguments.scenario#: bpPath=#bpPath# bpLine=#arguments.bpLine#", true );

		// Agent mode can only verify a breakpoint on a template once its
		// class has been compiled. The included file isn't compiled until
		// it's first run via cfinclude, so warm it up with a throwaway
		// request before setting the breakpoint.
		triggerArtifact( arguments.httpPath, {}, arguments.allowErrors );
		waitForHttpComplete();

		var bpResponse = dap.setBreakpoints( bpPath, [ arguments.bpLine ] );
		systemOutput( "#arguments.scenario#: setBreakpoints response=#serializeJSON( bpResponse )#", true );

		expect( bpResponse.body.breakpoints ).toHaveLength( 1 );
		expect( bpResponse.body.breakpoints[ 1 ].verified ).toBeTrue(
			"#arguments.scenario#: breakpoint on #arguments.includedFile#:#arguments.bpLine# should be verified"
		);

		triggerArtifact( arguments.httpPath, {}, arguments.allowErrors );
		sleep( 500 );

		var stopped = dap.waitForEvent( "stopped", 3000 );
		expect( stopped.body.reason ).toBe( "breakpoint" );

		var frame = getTopFrame( stopped.body.threadId );
		systemOutput( "#arguments.scenario#: top frame=#serializeJSON( frame )#", true );

		// Strict suffix match — "path ends with includedFile" rules out both
		// "path is some other Application.cfc" and "path contains includedFile
		// somewhere in the middle via coincidence".
		_expectPathEndsWith( frame.source.path, arguments.includedFile,
			"#arguments.scenario#: top frame should be #arguments.includedFile#. Got: #frame.source.path#"
		);
		expect( frame.line ).toBe( arguments.bpLine,
			"#arguments.scenario#: top frame line should be #arguments.bpLine#, got #frame.line#"
		);

		cleanupThread( stopped.body.threadId );
		clearBreakpoints( bpPath );
	}

}
