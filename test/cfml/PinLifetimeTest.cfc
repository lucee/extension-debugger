/**
 * Per-frame pinning invariants — see LDEV-6339-per-frame-pinning spec doc.
 *
 * The legacy global LRU (50 entries, 10-minute TTL) holds synthetic debug
 * wrappers (MarkerTrait.Scope, PreBuiltGroup, query-as-array, cfcatch map)
 * by identity hash. Once total pin pressure exceeds the cap, older entries
 * evict — and because ValTracker holds everything via WeakReference, a GC
 * after eviction blanks the Variables panel for those entries.
 *
 * These tests exercise three failure modes the per-frame pinning refactor
 * resolves:
 *
 *  - Cross-frame: deep stack with a CFC per frame; older frames' scopes
 *    must still expand after pin churn from newer frames.
 *  - PreBuiltGroup GC race: functions/accessors sub-groups are registered
 *    without ever calling pin() — only the weak ref holds them. A GC
 *    between the parent expansion and the sub-group click blanks them.
 *  - Single-frame batch: 60 CFC expansions in one frame must all remain
 *    expandable; LRU eviction silently drops the earliest ones.
 *
 * All native-only — agent mode keeps the legacy LRU per the spec's
 * "agent is LTS" call.
 */
component extends="org.lucee.cfml.test.LuceeTestCase" labels="dap" {

	include "DapTestCase.cfm";

	variables.deepStackTarget = "";
	variables.manyCfcsTarget = "";
	variables.richTarget = "";

	variables.lines = {
		deepStack: 23,    // pin-deep-stack-target.cfm: var breakpointMarker = "stop"; (bottom of recursion)
		manyCfcs: 21,     // pin-many-cfcs-target.cfm: var breakpointMarker = "stop";
		richDebug: 9      // rich-component-target.cfm: var debugLine = "inspect here";
	};

	function beforeAll() {
		setupDap();
		variables.deepStackTarget = getArtifactPath( "pin-deep-stack-target.cfm" );
		variables.manyCfcsTarget = getArtifactPath( "pin-many-cfcs-target.cfm" );
		variables.richTarget = getArtifactPath( "rich-component-target.cfm" );
	}

	function run( testResults, testBox ) {
		describe( "DAP per-frame pin lifetime", function() {

			beforeEach( function() {
				dap.drainEvents();
			} );

			afterEach( function() {
				clearBreakpoints();

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

			// Cross-frame survival: with the legacy 50-entry LRU, walking through ~4
			// frames worth of CFC expansions evicts the deepest frame's MarkerTrait.Scope
			// markers. A forced GC sweeps the weak refs and the saved variablesReference
			// resolves to nothing — Variables panel goes blank for that frame.
			it( title="cross-frame: oldest frame's CFC sub-group still expands after pin churn across ~8 frames + GC", body=function() {
				dap.setBreakpoints( variables.deepStackTarget, [ lines.deepStack ] );
				triggerArtifact( "pin-deep-stack-target.cfm" );

				var stopped = dap.waitForEvent( "stopped", 3000 );
				var threadId = stopped.body.threadId;

				var stackResponse = dap.stackTrace( threadId );
				var frames = stackResponse.body.stackFrames;
				expect( frames.len() ).toBeGTE( 8, "Expected ≥8 frames from frameDeep(8); got #frames.len()#" );

				// Phase 1 — pick the OLDEST frame that owns a myCfc local (last frameDeep frame),
				// expand its CFC, and save the `variables` sub-group ref. Under per-frame pinning
				// this stays alive until the frame resumes. Under the legacy LRU it gets evicted
				// during phase 2 below.
				var oldestFrame = frames[ frames.len() - 1 ];  // outermost frameDeep frame (skip cfm entry)
				var oldestLocal = getScopeByName( oldestFrame.id, "Local" );
				var oldestCfc = getVariableByName( oldestLocal.variablesReference, "myCfc" );
				var oldestCfcGroups = dap.getVariables( oldestCfc.variablesReference );
				expect( oldestCfcGroups.body.variables.len() ).toBeGT( 0, "Sanity: oldest frame's CFC should expand initially" );
				var oldestVariablesGroup = "";
				for ( var grp in oldestCfcGroups.body.variables ) {
					if ( grp.name == "variables" ) {
						oldestVariablesGroup = grp;
						break;
					}
				}
				expect( oldestVariablesGroup ).notToBeEmpty( "RichComponent should have a non-empty variables sub-group" );
				var savedOldestRef = oldestVariablesGroup.variablesReference;

				// Phase 2 — churn pins by visiting every other frame and expanding its myCfc.
				// Each frame visit adds ~14 init pins + ~3 sub-group pins. ~8 frames × ~17
				// pins easily exceeds the 50-entry LRU, evicting the oldest frame's markers.
				for ( var i = 1; i <= frames.len() - 1; i++ ) {
					try {
						var f = frames[ i ];
						var fLocal = getScopeByName( f.id, "Local" );
						var fLocalVars = dap.getVariables( fLocal.variablesReference );
						for ( var v in fLocalVars.body.variables ) {
							if ( v.name == "myCfc" && v.variablesReference > 0 ) {
								dap.getVariables( v.variablesReference );
								break;
							}
						}
					} catch ( any e ) {
						systemOutput( "phase2 frame #i# walk ignored: #e.message#", true );
					}
				}

				// Phase 3 — force GC on the debuggee so any LRU-evicted weak refs get swept.
				// Without this the test is flaky: eviction alone doesn't blank the panel,
				// only the eviction + GC combination does.
				dap.evaluate( frames[ 1 ].id, "createObject('java','java.lang.System').gc()" );

				// Phase 4 — re-expand the oldest frame's saved variables sub-group.
				// Per-frame pinning: still non-empty. Legacy LRU + GC: empty / error.
				var revisit = dap.getVariables( savedOldestRef );
				expect( revisit.success ).toBeTrue( "re-expanding oldest frame's variables sub-group must succeed; got: #serializeJSON( revisit )#" );
				expect( revisit.body.variables.len() ).toBeGT( 0,
					"oldest frame's variables sub-group blanked after pin churn + GC — "
					& "saved variablesReference no longer resolves to RichComponent's privateData. "
					& "Got: #serializeJSON( revisit.body )#"
				);

				cleanupThread( threadId );
			}, skip=notNativeMode() );

			// PreBuiltGroup is registered via valTracker but never pinned. Only the weak
			// ref holds it. A GC between the parent CFC expansion and the user clicking
			// the functions/accessors sub-group blanks those two groups.
			it( title="PreBuiltGroup: functions sub-group survives a GC between parent expansion and sub-group click", body=function() {
				dap.setBreakpoints( variables.richTarget, [ lines.richDebug ] );
				triggerArtifact( "rich-component-target.cfm" );

				var stopped = dap.waitForEvent( "stopped", 3000 );
				var threadId = stopped.body.threadId;

				var frame = getTopFrame( threadId );
				var localScope = getScopeByName( frame.id, "Local" );
				var richCfc = getVariableByName( localScope.variablesReference, "richComponent" );
				var groups = dap.getVariables( richCfc.variablesReference );

				// Resolve the functions sub-group's variablesReference. Its target is the
				// MarkerTrait.PreBuiltGroup(entries) — registered into valTracker but never
				// pinned to the static LRU. The weak ref is the only thing holding it.
				var functionsGroup = "";
				for ( var grp in groups.body.variables ) {
					if ( grp.name == "functions" ) {
						functionsGroup = grp;
						break;
					}
				}
				expect( functionsGroup ).notToBeEmpty( "RichComponent expansion should expose `functions` sub-group" );
				var savedFunctionsRef = functionsGroup.variablesReference;

				// Force GC on the debuggee while the parent is still suspended. The user
				// has not yet clicked the sub-group — exactly the race the spec describes.
				dap.evaluate( frame.id, "createObject('java','java.lang.System').gc()" );

				// Click the sub-group. Per-frame pinning: entries still resolve. Without
				// the pin: empty / 'variablesReference not found'.
				var click = dap.getVariables( savedFunctionsRef );
				expect( click.success ).toBeTrue( "PreBuiltGroup expansion after GC must succeed; got: #serializeJSON( click )#" );
				expect( click.body.variables.len() ).toBeGT( 0,
					"functions sub-group blanked by GC — PreBuiltGroup was never pinned. "
					& "Got: #serializeJSON( click.body )#"
				);

				cleanupThread( threadId );
			}, skip=notNativeMode() );

			// Single-frame batch: 60 CFC expansions in one frame. All saved
			// variablesReferences must remain expandable while the frame is suspended.
			// Under the 50-entry LRU the earliest 10+ get evicted; per-frame pinning
			// holds the whole batch.
			it( title="single frame: all of 60 CFC expansions still resolve after the batch + GC", body=function() {
				dap.setBreakpoints( variables.manyCfcsTarget, [ lines.manyCfcs ] );
				triggerArtifact( "pin-many-cfcs-target.cfm" );

				var stopped = dap.waitForEvent( "stopped", 3000 );
				var threadId = stopped.body.threadId;

				var frame = getTopFrame( threadId );
				var localScope = getScopeByName( frame.id, "Local" );

				// Grab the cfcs array and its first-element refs so we can re-expand later.
				var cfcsArray = getVariableByName( localScope.variablesReference, "cfcs" );
				var cfcsEntries = dap.getVariables( cfcsArray.variablesReference );
				expect( cfcsEntries.body.variables.len() ).toBeGTE( 60, "Expected ≥60 CFC entries in cfcs[]; got #cfcsEntries.body.variables.len()#" );

				// Phase 1 — expand every CFC and save its first sub-group's variablesReference.
				// Each expansion adds 3-4 pins to the legacy LRU. After ~13 expansions the cap
				// is hit and earliest entries start evicting.
				var savedRefs = [];
				for ( var entry in cfcsEntries.body.variables ) {
					if ( entry.variablesReference <= 0 ) continue;
					var groups = dap.getVariables( entry.variablesReference );
					if ( groups.body.variables.len() == 0 ) continue;
					savedRefs.append( groups.body.variables[ 1 ].variablesReference );
				}
				expect( savedRefs.len() ).toBeGTE( 60, "Expected ≥60 saved sub-group refs; got #savedRefs.len()#" );

				// Phase 2 — force GC. Any LRU-evicted weak refs from the earliest
				// expansions get swept here.
				dap.evaluate( frame.id, "createObject('java','java.lang.System').gc()" );

				// Phase 3 — re-walk every saved ref. Per-frame pinning: all alive.
				// Legacy LRU + GC: the earliest ones are blank.
				var blanked = [];
				for ( var i = 1; i <= savedRefs.len(); i++ ) {
					var revisit = dap.getVariables( savedRefs[ i ] );
					if ( !revisit.success || revisit.body.variables.len() == 0 ) {
						blanked.append( i );
					}
				}
				expect( blanked.len() ).toBe( 0,
					"#blanked.len()# of #savedRefs.len()# CFC sub-groups blanked after the batch + GC. "
					& "Blanked indices: #serializeJSON( blanked )#"
				);

				cleanupThread( threadId );
			}, skip=notNativeMode() );

		} );
	}
}
