/**
 * Expanding a Component in the Variables panel renders named sub-groups,
 * with empty groups omitted in both modes.
 *
 * Native mode (Lucee 7.1+): this / variables / static / functions / accessors.
 * `functions` and `accessors` render full signatures derived from
 * `cfc.getMetaData(pc)`.
 *
 * Agent mode: this / variables / static only. No metadata-derived groups
 * because the lookup needs a frameId→PageContext resolver that only
 * NativeLuceeVm registers. Tests that depend on the metadata groups are
 * gated `skip=!isNativeMode()`.
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

			it( title="expanding a Component exposes the expected groups and omits empty ones (this/static here)", body=function() {
				dap.setBreakpoints( variables.targetFile, [ lines.debugLine ] );
				triggerArtifact( "metadata-component-target.cfm" );

				var stopped = dap.waitForEvent( "stopped", 2000 );
				var threadId = stopped.body.threadId;

				var frame = getTopFrame( threadId );
				var localComponent = getVariableByName( getScopeByName( frame.id, "Local" ).variablesReference, "localComponent" );

				var response = dap.getVariables( localComponent.variablesReference );
				expect( response.success ).toBeTrue( "Expanding a Component must not error out the variables request" );

				var entryNames = response.body.variables.map( function( v ) { return v.name; } );
				expect( entryNames ).toInclude( "variables", "Component expansion should expose `variables`. Got: #serializeJSON( entryNames )#" );
				expect( entryNames ).toInclude( "functions", "Component expansion should expose `functions`" );
				expect( entryNames ).toInclude( "accessors", "Component expansion should expose `accessors`" );
				// SampleComponent has no `static {}` block — empty group should be omitted
				expect( entryNames ).notToInclude( "static", "Empty `static` group should be omitted. Got: #serializeJSON( entryNames )#" );
				// SampleComponent's `this` scope contains only UDFs (greet + accessors), which
				// have been moved to the dedicated `functions`/`accessors` groups — `this`
				// is effectively empty after filtering and should be omitted.
				expect( entryNames ).notToInclude( "this", "Empty `this` (UDF-only public surface) should be omitted. Got: #serializeJSON( entryNames )#" );

				cleanupThread( threadId );
			}, skip=!isNativeMode() );

			it( title="functions group exposes UDFImpl methods", body=function() {
				dap.setBreakpoints( variables.targetFile, [ lines.debugLine ] );
				triggerArtifact( "metadata-component-target.cfm" );

				var stopped = dap.waitForEvent( "stopped", 2000 );
				var threadId = stopped.body.threadId;

				var frame = getTopFrame( threadId );
				var localComponent = getVariableByName( getScopeByName( frame.id, "Local" ).variablesReference, "localComponent" );
				var functionsGroup = getVariableByName( localComponent.variablesReference, "functions" );

				var members = dap.getVariables( functionsGroup.variablesReference ).body.variables;
				var memberNames = members.map( function( v ) { return v.name; } );
				expect( memberNames ).toInclude( "greet", "`functions` group should expose declared methods. Got: #serializeJSON( memberNames )#" );

				// signature comes from getMetaData(cfc).functions — should render as `function greet(required string who) : <returntype>`
				var greet = getVariableByName( functionsGroup.variablesReference, "greet" );
				expect( greet.value ).toMatch( "function\s+greet\(.*who.*\)", "greet signature should include name + arg. Got: #greet.value#" );

				cleanupThread( threadId );
			}, skip=!isNativeMode() );

			it( title="accessors group exposes generated getter/setter pairs with derived signatures", body=function() {
				dap.setBreakpoints( variables.targetFile, [ lines.debugLine ] );
				triggerArtifact( "metadata-component-target.cfm" );

				var stopped = dap.waitForEvent( "stopped", 2000 );
				var threadId = stopped.body.threadId;

				var frame = getTopFrame( threadId );
				var localComponent = getVariableByName( getScopeByName( frame.id, "Local" ).variablesReference, "localComponent" );
				var accessorsGroup = getVariableByName( localComponent.variablesReference, "accessors" );

				var members = dap.getVariables( accessorsGroup.variablesReference ).body.variables;
				var memberNames = members.map( function( v ) { return v.name; } );
				expect( memberNames ).toInclude( "getFoo", "`accessors` group should expose generated getter. Got: #serializeJSON( memberNames )#" );
				expect( memberNames ).toInclude( "setFoo", "`accessors` group should expose generated setter" );

				// Auto-generated accessor signatures derived from `property name="foo" type="string"`.
				var getter = getVariableByName( accessorsGroup.variablesReference, "getFoo" );
				expect( getter.value ).toMatch( "function\s+getFoo\(\)\s*:\s*string", "getter signature should be `function getFoo() : string`. Got: #getter.value#" );

				var setter = getVariableByName( accessorsGroup.variablesReference, "setFoo" );
				expect( setter.value ).toMatch( "function\s+setFoo\(required\s+string\s+foo\)", "setter signature should be `function setFoo(required string foo)`. Got: #setter.value#" );

				cleanupThread( threadId );
			}, skip=!isNativeMode() );

		} );
	}
}
