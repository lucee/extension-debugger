/**
 * Expanding a Component in the Variables panel must return its this /
 * variables / static scope entries without blowing up the JSON-RPC channel.
 *
 * Regression guard: ComponentImpl is only mixed with
 * `ComponentScopeMarkerTraitShim` in agent mode (via bytecode injection).
 * In native mode the cast at CfValueDebuggerBridge.maybeNull_asValue
 * used to ClassCastException, killing the `variables` request and
 * blanking the Variables panel from that point on.
 */
component extends="org.lucee.cfml.test.LuceeTestCase" labels="dap" {

	include "DapTestCase.cfm";

	variables.targetFile = "";

	// Line numbers in artifacts/metadata-component-target.cfm — keep in sync.
	variables.lines = {
		debugLine: 9 // var debugLine = "inspect here";
	};

	function beforeAll() {
		setupDap();
		variables.targetFile = getArtifactPath( "metadata-component-target.cfm" );
	}

	function run( testResults, testBox ) {
		describe( "DAP Component variables expansion", function() {

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

			it( title="expanding a Component returns this/variables/static without ClassCastException", body=function() {
				dap.setBreakpoints( variables.targetFile, [ lines.debugLine ] );
				triggerArtifact( "metadata-component-target.cfm" );

				var stopped = dap.waitForEvent( "stopped", 2000 );
				var threadId = stopped.body.threadId;

				var frame = getTopFrame( threadId );
				var localComponent = getVariableByName( getScopeByName( frame.id, "Local" ).variablesReference, "localComponent" );

				var response = dap.getVariables( localComponent.variablesReference );
				expect( response.success ).toBeTrue( "Expanding a Component must not error out the variables request" );

				var entryNames = response.body.variables.map( function( v ) { return v.name; } );
				expect( entryNames ).toInclude( "this", "Component expansion should expose `this` scope. Got: #serializeJSON( entryNames )#" );
				expect( entryNames ).toInclude( "variables", "Component expansion should expose `variables` scope" );
				expect( entryNames ).toInclude( "static", "Component expansion should expose `static` scope" );

				cleanupThread( threadId );
			}, skip=!isNativeMode() );

		} );
	}
}
