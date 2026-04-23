/**
 * Tests for debug console completions/autocomplete functionality.
 *
 * BDD style — skip= uses capabilities probed at include-time via DapTestCase.cfm.
 */
component extends="org.lucee.cfml.test.LuceeTestCase" labels="dap" {

	include "DapTestCase.cfm";

	variables.targetFile = "";

	// Line numbers in completions-target.cfm — keep in sync with the file.
	// Validated by the "target line is a valid breakpoint location" spec below.
	variables.lines = {
		debugLine: 23  // var stopHere = true;
	};

	function beforeAll() {
		setupDap();
		variables.targetFile = getArtifactPath( "completions-target.cfm" );
	}

	function run( testResults, testBox ) {
		describe( "DAP completions", function() {

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
				var locations = dap.breakpointLocations( variables.targetFile, 1, 35 );
				var validLines = locations.body.breakpoints.map( function( bp ) { return bp.line; } );

				systemOutput( "#variables.targetFile# valid lines: #serializeJSON( validLines )#", true );

				for ( var key in variables.lines ) {
					var line = variables.lines[ key ];
					expect( validLines ).toInclude( line, "#variables.targetFile# line #line# (#key#) should be a valid breakpoint location" );
				}
			}, skip=notSupportsBreakpointLocations() );

			it( title="returns a non-empty completions list for a known prefix", body=function() {
				dap.setBreakpoints( variables.targetFile, [ lines.debugLine ] );
				triggerArtifact( "completions-target.cfm" );

				var stopped = dap.waitForEvent( "stopped", 2000 );
				var threadId = stopped.body.threadId;

				var frame = getTopFrame( threadId );

				var completionsResponse = dap.completions( frame.id, "my" );

				expect( completionsResponse.body ).toHaveKey( "targets" );
				expect( completionsResponse.body.targets.len() ).toBeGT( 0, "Should return completions" );

				cleanupThread( threadId );
			}, skip=notSupportsCompletions() );

			it( title="suggests local variables matching the prefix 'my'", body=function() {
				dap.setBreakpoints( variables.targetFile, [ lines.debugLine ] );
				triggerArtifact( "completions-target.cfm" );

				var stopped = dap.waitForEvent( "stopped", 2000 );
				var threadId = stopped.body.threadId;

				var frame = getTopFrame( threadId );

				var completionsResponse = dap.completions( frame.id, "my" );
				var labels = completionsResponse.body.targets.map( function( t ) { return t.label; } );

				expect( labels ).toInclude( "myString" );
				expect( labels ).toInclude( "myNumber" );
				expect( labels ).toInclude( "myStruct" );
				expect( labels ).toInclude( "myArray" );

				cleanupThread( threadId );
			}, skip=notSupportsCompletions() );

			it( title="suggests struct keys after dot-notation prefix 'myStruct.'", body=function() {
				dap.setBreakpoints( variables.targetFile, [ lines.debugLine ] );
				triggerArtifact( "completions-target.cfm" );

				var stopped = dap.waitForEvent( "stopped", 2000 );
				var threadId = stopped.body.threadId;

				var frame = getTopFrame( threadId );

				var completionsResponse = dap.completions( frame.id, "myStruct." );
				var labels = completionsResponse.body.targets.map( function( t ) { return t.label; } );

				expect( labels ).toInclude( "firstName" );
				expect( labels ).toInclude( "lastName" );
				expect( labels ).toInclude( "address" );

				cleanupThread( threadId );
			}, skip=notSupportsCompletions() );

			it( title="suggests nested struct keys after 'myStruct.address.'", body=function() {
				dap.setBreakpoints( variables.targetFile, [ lines.debugLine ] );
				triggerArtifact( "completions-target.cfm" );

				var stopped = dap.waitForEvent( "stopped", 2000 );
				var threadId = stopped.body.threadId;

				var frame = getTopFrame( threadId );

				var completionsResponse = dap.completions( frame.id, "myStruct.address." );
				var labels = completionsResponse.body.targets.map( function( t ) { return t.label; } );

				expect( labels ).toInclude( "street" );
				expect( labels ).toInclude( "city" );

				cleanupThread( threadId );
			}, skip=notSupportsCompletions() );

			it( title="filters completions by partial input 'myStruct.f'", body=function() {
				dap.setBreakpoints( variables.targetFile, [ lines.debugLine ] );
				triggerArtifact( "completions-target.cfm" );

				var stopped = dap.waitForEvent( "stopped", 2000 );
				var threadId = stopped.body.threadId;

				var frame = getTopFrame( threadId );

				var completionsResponse = dap.completions( frame.id, "myStruct.f" );
				var labels = completionsResponse.body.targets.map( function( t ) { return t.label; } );

				expect( labels ).toInclude( "firstName" );
				expect( labels ).notToInclude( "lastName" );

				cleanupThread( threadId );
			}, skip=notSupportsCompletions() );

			it( title="suggests component methods after 'myComponent.'", body=function() {
				dap.setBreakpoints( variables.targetFile, [ lines.debugLine ] );
				triggerArtifact( "completions-target.cfm" );

				var stopped = dap.waitForEvent( "stopped", 2000 );
				var threadId = stopped.body.threadId;

				var frame = getTopFrame( threadId );

				var completionsResponse = dap.completions( frame.id, "myComponent." );
				var labels = completionsResponse.body.targets.map( function( t ) { return t.label; } );

				// SampleComponent exposes greet() + its `foo` property accessors (getFoo/setFoo).
				expect( labels ).toInclude( "greet" );

				cleanupThread( threadId );
			}, skip=notSupportsCompletions() );

			it( title="returns completions for empty input (local scope dump)", body=function() {
				dap.setBreakpoints( variables.targetFile, [ lines.debugLine ] );
				triggerArtifact( "completions-target.cfm" );

				var stopped = dap.waitForEvent( "stopped", 2000 );
				var threadId = stopped.body.threadId;

				var frame = getTopFrame( threadId );

				var completionsResponse = dap.completions( frame.id, "" );

				expect( completionsResponse.body.targets.len() ).toBeGT( 0, "Empty input should return completions" );

				cleanupThread( threadId );
			}, skip=notSupportsCompletions() );

		} );
	}
}
