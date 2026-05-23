/**
 * Tests for evaluate/expression functionality.
 *
 * BDD style — skip= uses capabilities probed at include-time via DapTestCase.cfm.
 */
component extends="org.lucee.cfml.test.LuceeTestCase" labels="dap" {

	include "DapTestCase.cfm";

	variables.targetFile = "";

	// Line numbers in evaluate-target.cfm — keep in sync with the file.
	variables.lines = {
		debugLine: 26  // return localVar & " - " & dataName;
	};

	function beforeAll() {
		setupDap();
		variables.targetFile = getArtifactPath( "evaluate-target.cfm" );
	}

	function run( testResults, testBox ) {
		describe( "DAP evaluate", function() {

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

			it( title="native: target debugLine is a valid breakpoint location", body=function() {
				var locations = dap.breakpointLocations( variables.targetFile, 1, 40 );
				var validLines = locations.body.breakpoints.map( function( bp ) { return bp.line; } );

				systemOutput( "#variables.targetFile# valid lines: #serializeJSON( validLines )#", true );

				for ( var key in variables.lines ) {
					var line = variables.lines[ key ];
					expect( validLines ).toInclude( line, "#variables.targetFile# line #line# (#key#) should be a valid breakpoint location" );
				}
			}, skip=notSupportsBreakpointLocations() );

			it( title="evaluates a simple arithmetic expression", body=function() {
				dap.setBreakpoints( variables.targetFile, [ lines.debugLine ] );
				triggerArtifact( "evaluate-target.cfm" );

				var stopped = dap.waitForEvent( "stopped", 2000 );
				var threadId = stopped.body.threadId;
				var frame = getTopFrame( threadId );

				var evalResponse = dap.evaluate( frame.id, "1 + 1" );

				expect( evalResponse.body.result ).toBe( "2" );

				cleanupThread( threadId );
			}, skip=notSupportsEvaluate() );

			it( title="evaluates a local string variable", body=function() {
				dap.setBreakpoints( variables.targetFile, [ lines.debugLine ] );
				triggerArtifact( "evaluate-target.cfm" );

				var stopped = dap.waitForEvent( "stopped", 2000 );
				var threadId = stopped.body.threadId;
				var frame = getTopFrame( threadId );

				var evalResponse = dap.evaluate( frame.id, "localVar" );

				expect( evalResponse.body.result ).toBe( '"local-value"' );

				cleanupThread( threadId );
			}, skip=notSupportsEvaluate() );

			it( title="evaluates a local numeric variable", body=function() {
				dap.setBreakpoints( variables.targetFile, [ lines.debugLine ] );
				triggerArtifact( "evaluate-target.cfm" );

				var stopped = dap.waitForEvent( "stopped", 2000 );
				var threadId = stopped.body.threadId;
				var frame = getTopFrame( threadId );

				var evalResponse = dap.evaluate( frame.id, "localNum" );

				expect( evalResponse.body.result ).toBe( "100" );

				cleanupThread( threadId );
			}, skip=notSupportsEvaluate() );

			it( title="evaluates a struct key access (localStruct.key1)", body=function() {
				dap.setBreakpoints( variables.targetFile, [ lines.debugLine ] );
				triggerArtifact( "evaluate-target.cfm" );

				var stopped = dap.waitForEvent( "stopped", 2000 );
				var threadId = stopped.body.threadId;
				var frame = getTopFrame( threadId );

				var evalResponse = dap.evaluate( frame.id, "localStruct.key1" );

				expect( evalResponse.body.result ).toBe( '"value1"' );

				cleanupThread( threadId );
			}, skip=notSupportsEvaluate() );

			it( title="evaluates a nested struct key (localStruct.nested.inner)", body=function() {
				dap.setBreakpoints( variables.targetFile, [ lines.debugLine ] );
				triggerArtifact( "evaluate-target.cfm" );

				var stopped = dap.waitForEvent( "stopped", 2000 );
				var threadId = stopped.body.threadId;
				var frame = getTopFrame( threadId );

				var evalResponse = dap.evaluate( frame.id, "localStruct.nested.inner" );

				expect( evalResponse.body.result ).toBe( '"deep"' );

				cleanupThread( threadId );
			}, skip=notSupportsEvaluate() );

			it( title="evaluates an array element access (localArray[2])", body=function() {
				dap.setBreakpoints( variables.targetFile, [ lines.debugLine ] );
				triggerArtifact( "evaluate-target.cfm" );

				var stopped = dap.waitForEvent( "stopped", 2000 );
				var threadId = stopped.body.threadId;
				var frame = getTopFrame( threadId );

				var evalResponse = dap.evaluate( frame.id, "localArray[2]" );

				expect( evalResponse.body.result ).toBe( "20" );

				cleanupThread( threadId );
			}, skip=notSupportsEvaluate() );

			it( title="evaluates arguments-scope access (arguments.data.name)", body=function() {
				dap.setBreakpoints( variables.targetFile, [ lines.debugLine ] );
				triggerArtifact( "evaluate-target.cfm" );

				var stopped = dap.waitForEvent( "stopped", 2000 );
				var threadId = stopped.body.threadId;
				var frame = getTopFrame( threadId );

				var evalResponse = dap.evaluate( frame.id, "arguments.data.name" );

				expect( evalResponse.body.result ).toBe( '"test-input"' );

				cleanupThread( threadId );
			}, skip=notSupportsEvaluate() );

			it( title="evaluates a string concatenation expression", body=function() {
				dap.setBreakpoints( variables.targetFile, [ lines.debugLine ] );
				triggerArtifact( "evaluate-target.cfm" );

				var stopped = dap.waitForEvent( "stopped", 2000 );
				var threadId = stopped.body.threadId;
				var frame = getTopFrame( threadId );

				var evalResponse = dap.evaluate( frame.id, "localVar & ' - ' & dataName" );

				expect( evalResponse.body.result ).toBe( '"local-value - test-input"' );

				cleanupThread( threadId );
			}, skip=notSupportsEvaluate() );

			it( title="evaluates a math expression with variables", body=function() {
				dap.setBreakpoints( variables.targetFile, [ lines.debugLine ] );
				triggerArtifact( "evaluate-target.cfm" );

				var stopped = dap.waitForEvent( "stopped", 2000 );
				var threadId = stopped.body.threadId;
				var frame = getTopFrame( threadId );

				var evalResponse = dap.evaluate( frame.id, "localNum * 2 + 50" );

				expect( evalResponse.body.result ).toBe( "250" );

				cleanupThread( threadId );
			}, skip=notSupportsEvaluate() );

			it( title="evaluates a built-in function call (len)", body=function() {
				dap.setBreakpoints( variables.targetFile, [ lines.debugLine ] );
				triggerArtifact( "evaluate-target.cfm" );

				var stopped = dap.waitForEvent( "stopped", 2000 );
				var threadId = stopped.body.threadId;
				var frame = getTopFrame( threadId );

				var evalResponse = dap.evaluate( frame.id, "len(localVar)" );

				expect( evalResponse.body.result ).toBe( "11" ); // "local-value" = 11 chars

				cleanupThread( threadId );
			}, skip=notSupportsEvaluate() );

			it( title="evaluates arrayLen on a local array", body=function() {
				dap.setBreakpoints( variables.targetFile, [ lines.debugLine ] );
				triggerArtifact( "evaluate-target.cfm" );

				var stopped = dap.waitForEvent( "stopped", 2000 );
				var threadId = stopped.body.threadId;
				var frame = getTopFrame( threadId );

				var evalResponse = dap.evaluate( frame.id, "arrayLen(localArray)" );

				expect( evalResponse.body.result ).toBe( "3" );

				cleanupThread( threadId );
			}, skip=notSupportsEvaluate() );

			// Regression for the cross-thread bleed risk in the old getAnySuspendedPageContext()
			// fallback: two concurrent requests both paused, resolving one thread's stale frame
			// must not silently grab the other thread's PC.
			it( title="multi-thread cross-bleed: stale frame id resolves to OWN request, not another concurrent thread's", body=function() {
				var targetFile = getArtifactPath( "multi-thread-target.cfm" );
				var multiThreadLines = { breakpoint: 16 };  // myCounter = 1;
				dap.setBreakpoints( targetFile, [ multiThreadLines.breakpoint ] );

				var handleA = triggerArtifactBackground( "multi-thread-target.cfm", { label: "A-value" } );
				var handleB = triggerArtifactBackground( "multi-thread-target.cfm", { label: "B-value" } );

				var stopped1 = dap.waitForEvent( "stopped", 5000 );
				var stopped2 = dap.waitForEvent( "stopped", 5000 );

				var threadId1 = stopped1.body.threadId;
				var threadId2 = stopped2.body.threadId;
				expect( threadId1 ).notToBe( threadId2, "Two concurrent requests should produce distinct threadIds" );

				var frame1 = getTopFrame( threadId1 );
				var frame2 = getTopFrame( threadId2 );

				// Sanity: each thread sees its OWN label, not the other's.
				var eval1 = dap.evaluate( frame1.id, "myLabel" );
				var eval2 = dap.evaluate( frame2.id, "myLabel" );
				expect( eval1.body.result ).notToBe( eval2.body.result,
					"Sanity: distinct threads should have distinct myLabel; got both='#eval1.body.result#'"
				);
				var seenLabels = [ eval1.body.result, eval2.body.result ];
				expect( seenLabels ).toInclude( '"A-value"' );
				expect( seenLabels ).toInclude( '"B-value"' );

				// Step thread 1 — its frames go into evictedFrameRequestId.
				// Thread 2 stays paused on its own frames.
				dap.stepOver( threadId1 );
				dap.waitForEvent( "stopped", 2000 );

				// Cross-bleed assertion: evaluating thread 1's STALE frame id
				// while thread 2 is also suspended must resolve to thread 1's
				// request invocation, not bleed to thread 2's.
				var staleEval = dap.evaluate( frame1.id, "myLabel" );
				expect( staleEval.body.result ).toBe( eval1.body.result,
					"Stale frame from thread #threadId1# should resolve to its OWN label "
					& "(#eval1.body.result#), not bleed to thread #threadId2# (#eval2.body.result#); got '#staleEval.body.result#'"
				);

				// Resume both threads + drain both background requests
				try { dap.continueThread( threadId1 ); } catch ( any e ) {}
				try { dap.continueThread( threadId2 ); } catch ( any e ) {}
				try { waitForBackgroundComplete( handleA, 5000 ); } catch ( any e ) {}
				try { waitForBackgroundComplete( handleB, 5000 ); } catch ( any e ) {}
			}, skip=( notSupportsEvaluate() || !isNativeMode() ) );

			// VSCode races stackTrace + evaluate after a stop; evaluate can arrive
			// with a frame id from the prior suspension, which mustn't leak as an error.
			it( title="evaluate against a stale frame id does not leak 'Frame not found' to the client", body=function() {
				dap.setBreakpoints( variables.targetFile, [ lines.debugLine ] );
				triggerArtifact( "evaluate-target.cfm" );

				var stopped = dap.waitForEvent( "stopped", 2000 );
				var threadId = stopped.body.threadId;
				var staleFrame = getTopFrame( threadId );
				var staleFrameId = staleFrame.id;

				// Step over: frames for this thread are evicted, the thread
				// re-suspends at the next instrumentation point, and a fresh
				// set of frame ids is minted on the next stackTrace fetch.
				dap.stepOver( threadId );
				dap.waitForEvent( "stopped", 2000 );

				var leaked = "";
				try {
					var resp = dap.evaluate( staleFrameId, "cgi" );
					leaked = resp.body.result ?: "";
				} catch ( DapClient.Error e ) {
					leaked = e.message;
				}
				expect( leaked ).notToInclude( "Frame not found",
					"evaluate against stale frame leaked internal id to client: '#leaked#'" );

				cleanupThread( threadId );
			}, skip=( notSupportsEvaluate() || !isNativeMode() ) );

			// Debug-console eval with no frame selected — server-side `evaluateNoFrame` path.
			// Single-thread cases land here; multi-thread cross-bleed lives in the per-frame
			// pinning work since `getAnySuspendedPageContext` non-determinism makes the
			// multi-thread variant flaky until the active-thread tracker lands.
			it( title="no frame: returns result against the suspended PC", body=function() {
				dap.setBreakpoints( variables.targetFile, [ lines.debugLine ] );
				triggerArtifact( "evaluate-target.cfm" );

				var stopped = dap.waitForEvent( "stopped", 2000 );
				var threadId = stopped.body.threadId;

				// no frameId — server falls back to evaluateNoFrame against any suspended PC
				var evalResponse = dap.evaluate( expression="1 + 1" );
				expect( evalResponse.body.result ).toBe( "2",
					"no-frame eval against a suspended PC should return result. Got: #serializeJSON( evalResponse.body )#" );

				cleanupThread( threadId );
			}, skip=( notSupportsEvaluate() || !isNativeMode() ) );

			it( title="no frame + hover context: returns error, not a result", body=function() {
				dap.setBreakpoints( variables.targetFile, [ lines.debugLine ] );
				triggerArtifact( "evaluate-target.cfm" );

				var stopped = dap.waitForEvent( "stopped", 2000 );
				var threadId = stopped.body.threadId;

				// hover requests fire constantly; the server short-circuits with an error
				// when there's no frame rather than evaluating against an unrelated PC
				var caught = false;
				try {
					dap.evaluate( expression="1 + 1", context="hover" );
				} catch ( DapClient.Error e ) {
					caught = true;
				}
				expect( caught ).toBeTrue( "hover with no frame must produce an error response" );

				cleanupThread( threadId );
			}, skip=( notSupportsEvaluate() || !isNativeMode() ) );

			it( title="no frame + nothing paused: returns 'not paused' soft error", body=function() {
				// no breakpoint, no trigger — nothing is suspended
				var evalResponse = dap.evaluate( expression="1 + 1" );
				expect( evalResponse.body.result ).toInclude( "not paused",
					"no-frame eval with nothing suspended should surface the 'not paused' soft error. Got: #serializeJSON( evalResponse.body )#" );
			}, skip=( notSupportsEvaluate() || !isNativeMode() ) );

		} );
	}
}
