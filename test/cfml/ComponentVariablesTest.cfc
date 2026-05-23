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
	variables.richTargetFile = "";

	// Line numbers in artifacts/*-component-target.cfm — keep in sync.
	variables.lines = {
		debugLine: 9 // var debugLine = "inspect here";
	};

	function beforeAll() {
		setupDap();
		variables.targetFile = getArtifactPath( "metadata-component-target.cfm" );
		variables.richTargetFile = getArtifactPath( "rich-component-target.cfm" );
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

			it( title="rich CFC: every sub-group is present and renders its members", body=function() {
				dap.setBreakpoints( variables.richTargetFile, [ lines.debugLine ] );
				triggerArtifact( "rich-component-target.cfm" );

				var stopped = dap.waitForEvent( "stopped", 2000 );
				var threadId = stopped.body.threadId;

				var frame = getTopFrame( threadId );
				var richComponent = getVariableByName( getScopeByName( frame.id, "Local" ).variablesReference, "richComponent" );

				var response = dap.getVariables( richComponent.variablesReference );
				expect( response.success ).toBeTrue( "Rich CFC expansion must not error out" );

				var entryNames = response.body.variables.map( function( v ) { return v.name; } );
				expect( entryNames ).toInclude( "this", "RichComponent has `this.publicData` — `this` should be present. Got: #serializeJSON( entryNames )#" );
				expect( entryNames ).toInclude( "variables", "RichComponent assigns to `variables` scope — should be present" );
				expect( entryNames ).toInclude( "static", "RichComponent has a non-empty `static {}` block — should be present" );
				expect( entryNames ).toInclude( "functions", "RichComponent declares public/private/package methods — `functions` should be present" );
				expect( entryNames ).toInclude( "accessors", "RichComponent has accessor properties — `accessors` should be present" );

				// static scope: members from the `static {}` block
				var staticGroup = getVariableByName( richComponent.variablesReference, "static" );
				var staticMemberNames = dap.getVariables( staticGroup.variablesReference ).body.variables.map( function( v ) { return v.name; } );
				expect( staticMemberNames ).toInclude( "staticCounter", "static group should expose `staticCounter`. Got: #serializeJSON( staticMemberNames )#" );
				expect( staticMemberNames ).toInclude( "staticLabel", "static group should expose `staticLabel`" );

				// this scope: non-UDF members assigned in init()
				var thisGroup = getVariableByName( richComponent.variablesReference, "this" );
				var thisMemberNames = dap.getVariables( thisGroup.variablesReference ).body.variables.map( function( v ) { return v.name; } );
				expect( thisMemberNames ).toInclude( "publicData", "this group should expose `publicData`. Got: #serializeJSON( thisMemberNames )#" );

				// variables scope: members assigned via `variables.privateData = ...`
				var variablesGroup = getVariableByName( richComponent.variablesReference, "variables" );
				var variablesMemberNames = dap.getVariables( variablesGroup.variablesReference ).body.variables.map( function( v ) { return v.name; } );
				expect( variablesMemberNames ).toInclude( "privateData", "variables group should expose `privateData`. Got: #serializeJSON( variablesMemberNames )#" );

				cleanupThread( threadId );
			}, skip=!isNativeMode() );

			it( title="accessors group honours per-property getter=false / setter=false overrides", body=function() {
				dap.setBreakpoints( variables.richTargetFile, [ lines.debugLine ] );
				triggerArtifact( "rich-component-target.cfm" );

				var stopped = dap.waitForEvent( "stopped", 2000 );
				var threadId = stopped.body.threadId;

				var frame = getTopFrame( threadId );
				var richComponent = getVariableByName( getScopeByName( frame.id, "Local" ).variablesReference, "richComponent" );
				var accessorsGroup = getVariableByName( richComponent.variablesReference, "accessors" );

				var memberNames = dap.getVariables( accessorsGroup.variablesReference ).body.variables.map( function( v ) { return v.name; } );

				// alpha: default — both getter and setter
				expect( memberNames ).toInclude( "getAlpha", "alpha should have a getter. Got: #serializeJSON( memberNames )#" );
				expect( memberNames ).toInclude( "setAlpha", "alpha should have a setter" );

				// beta: getter="false" — only setter
				expect( memberNames ).notToInclude( "getBeta", "beta declared getter='false' — no getter expected" );
				expect( memberNames ).toInclude( "setBeta", "beta should still expose a setter" );

				// gamma: setter="false" — only getter
				expect( memberNames ).toInclude( "getGamma", "gamma should still expose a getter" );
				expect( memberNames ).notToInclude( "setGamma", "gamma declared setter='false' — no setter expected" );

				cleanupThread( threadId );
			}, skip=!isNativeMode() );

			it( title="functions group renders private and package access modifiers in the signature", body=function() {
				dap.setBreakpoints( variables.richTargetFile, [ lines.debugLine ] );
				triggerArtifact( "rich-component-target.cfm" );

				var stopped = dap.waitForEvent( "stopped", 2000 );
				var threadId = stopped.body.threadId;

				var frame = getTopFrame( threadId );
				var richComponent = getVariableByName( getScopeByName( frame.id, "Local" ).variablesReference, "richComponent" );
				var functionsGroup = getVariableByName( richComponent.variablesReference, "functions" );

				var helper = getVariableByName( functionsGroup.variablesReference, "helper" );
				expect( helper.value ).toMatch( "^private\s+function\s+helper\(", "private modifier should prefix the signature. Got: #helper.value#" );

				var pkgFn = getVariableByName( functionsGroup.variablesReference, "pkgFn" );
				expect( pkgFn.value ).toMatch( "^package\s+function\s+pkgFn\(", "package modifier should prefix the signature. Got: #pkgFn.value#" );

				// Public is the default — should NOT be prefixed
				var doStuff = getVariableByName( functionsGroup.variablesReference, "doStuff" );
				expect( doStuff.value ).notToMatch( "^public\s+function", "public is the default — no `public` prefix expected. Got: #doStuff.value#" );

				cleanupThread( threadId );
			}, skip=!isNativeMode() );

			it( title="variables sub-group expands flat (no recursive sub-grouping)", body=function() {
				dap.setBreakpoints( variables.richTargetFile, [ lines.debugLine ] );
				triggerArtifact( "rich-component-target.cfm" );

				var stopped = dap.waitForEvent( "stopped", 2000 );
				var threadId = stopped.body.threadId;

				var frame = getTopFrame( threadId );
				var richComponent = getVariableByName( getScopeByName( frame.id, "Local" ).variablesReference, "richComponent" );
				var variablesGroup = getVariableByName( richComponent.variablesReference, "variables" );

				var members = dap.getVariables( variablesGroup.variablesReference ).body.variables;
				var memberNames = members.map( function( v ) { return v.name; } );

				// flat expansion: should contain real keys, NOT synthetic sub-group names
				expect( memberNames ).toInclude( "privateData", "variables sub-group should expose `privateData` (init() assignment). Got: #serializeJSON( memberNames )#" );
				expect( memberNames ).notToInclude( "functions", "variables sub-group must NOT recursively render the `functions` sub-group" );
				expect( memberNames ).notToInclude( "accessors", "variables sub-group must NOT recursively render the `accessors` sub-group" );
				expect( memberNames ).notToInclude( "static", "variables sub-group must NOT recursively render the `static` sub-group" );

				cleanupThread( threadId );
			}, skip=!isNativeMode() );

			it( title="variables sub-group hides the redundant `this` self-ref key", body=function() {
				dap.setBreakpoints( variables.richTargetFile, [ lines.debugLine ] );
				triggerArtifact( "rich-component-target.cfm" );

				var stopped = dap.waitForEvent( "stopped", 2000 );
				var threadId = stopped.body.threadId;

				var frame = getTopFrame( threadId );
				var richComponent = getVariableByName( getScopeByName( frame.id, "Local" ).variablesReference, "richComponent" );
				var variablesGroup = getVariableByName( richComponent.variablesReference, "variables" );

				var members = dap.getVariables( variablesGroup.variablesReference ).body.variables;
				var memberNames = members.map( function( v ) { return uCase( v.name ); } );

				// Lucee's variables scope contains a `this` self-ref. Without filtering it,
				// expanding variables opens this → variables → this → ... ad infinitum.
				// Filter keeps real data members; user reaches `this` via the cfc's own `this` sub-group.
				expect( memberNames ).notToInclude( "THIS", "variables sub-group must hide the self-referencing `this` key. Got: #serializeJSON( memberNames )#" );
				expect( memberNames ).toInclude( "PRIVATEDATA", "variables sub-group should still expose real data (privateData)" );

				cleanupThread( threadId );
			}, skip=!isNativeMode() );

			it( title="static sub-group expands flat (no recursive sub-grouping)", body=function() {
				dap.setBreakpoints( variables.richTargetFile, [ lines.debugLine ] );
				triggerArtifact( "rich-component-target.cfm" );

				var stopped = dap.waitForEvent( "stopped", 2000 );
				var threadId = stopped.body.threadId;

				var frame = getTopFrame( threadId );
				var richComponent = getVariableByName( getScopeByName( frame.id, "Local" ).variablesReference, "richComponent" );
				var staticGroup = getVariableByName( richComponent.variablesReference, "static" );

				var members = dap.getVariables( staticGroup.variablesReference ).body.variables;
				var memberNames = members.map( function( v ) { return v.name; } );

				expect( memberNames ).toInclude( "staticCounter", "static sub-group should expose `staticCounter`. Got: #serializeJSON( memberNames )#" );
				expect( memberNames ).notToInclude( "functions", "static sub-group must NOT recursively render the `functions` sub-group" );
				expect( memberNames ).notToInclude( "accessors", "static sub-group must NOT recursively render the `accessors` sub-group" );

				cleanupThread( threadId );
			}, skip=!isNativeMode() );

			it( title="Component child reports namedVariables upper bound without paying metadata cost", body=function() {
				dap.setBreakpoints( variables.richTargetFile, [ lines.debugLine ] );
				triggerArtifact( "rich-component-target.cfm" );

				var stopped = dap.waitForEvent( "stopped", 2000 );
				var threadId = stopped.body.threadId;

				var frame = getTopFrame( threadId );
				var richComponent = getVariableByName( getScopeByName( frame.id, "Local" ).variablesReference, "richComponent" );

				// lazy-count: parent declares 5 (upper bound — this/variables/static/functions/accessors)
				// without doing the per-CFC getMetaData call upfront. Real sub-groups materialise on expand.
				expect( richComponent.namedVariables ).toBe( 5, "Component child should declare namedVariables=5 as upper bound. Got: #richComponent.namedVariables#" );

				cleanupThread( threadId );
			}, skip=!isNativeMode() );

			it( title="function signature renders required vs optional args distinctly", body=function() {
				dap.setBreakpoints( variables.richTargetFile, [ lines.debugLine ] );
				triggerArtifact( "rich-component-target.cfm" );

				var stopped = dap.waitForEvent( "stopped", 2000 );
				var threadId = stopped.body.threadId;

				var frame = getTopFrame( threadId );
				var richComponent = getVariableByName( getScopeByName( frame.id, "Local" ).variablesReference, "richComponent" );
				var functionsGroup = getVariableByName( richComponent.variablesReference, "functions" );
				var doStuff = getVariableByName( functionsGroup.variablesReference, "doStuff" );

				// required string name → "required string name"
				expect( doStuff.value ).toMatch( "required\s+string\s+name", "required arg should be prefixed `required`. Got: #doStuff.value#" );

				// numeric count=1 (optional) → "numeric count" — no `required` prefix
				expect( doStuff.value ).toMatch( "numeric\s+count(?!\s*=)", "optional arg should NOT be prefixed `required`. Got: #doStuff.value#" );
				expect( doStuff.value ).notToMatch( "required\s+numeric\s+count", "optional arg should NOT be marked required" );

				// boolean flag (optional, no default) → "boolean flag" — no `required` prefix
				expect( doStuff.value ).notToMatch( "required\s+boolean\s+flag", "optional arg without default should NOT be marked required" );

				cleanupThread( threadId );
			}, skip=!isNativeMode() );

		} );
	}
}
