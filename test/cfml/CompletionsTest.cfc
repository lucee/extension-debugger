/**
 * Tests for debug console completions/autocomplete functionality.
 *
 * BDD style — runtime guards inside each `it` (not `skip=`, see
 * feedback_testbox_style memory + DelayedVerifyTest.cfc:44-48).
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

			it( "native: target debugLine is a valid breakpoint location", function() {
				if ( !supportsBreakpointLocations() ) {
					systemOutput( "skipping: breakpointLocations not supported", true );
					return;
				}

				var locations = dap.breakpointLocations( variables.targetFile, 1, 35 );
				var validLines = locations.body.breakpoints.map( function( bp ) { return bp.line; } );

				systemOutput( "#variables.targetFile# valid lines: #serializeJSON( validLines )#", true );

				for ( var key in variables.lines ) {
					var line = variables.lines[ key ];
					expect( validLines ).toInclude( line, "#variables.targetFile# line #line# (#key#) should be a valid breakpoint location" );
				}
			} );

			it( "returns a non-empty completions list for a known prefix", function() {
				if ( !supportsCompletions() ) {
					systemOutput( "skipping: completions not supported", true );
					return;
				}

				dap.setBreakpoints( variables.targetFile, [ lines.debugLine ] );
				triggerArtifact( "completions-target.cfm" );

				var stopped = dap.waitForEvent( "stopped", 2000 );
				var threadId = stopped.body.threadId;

				var frame = getTopFrame( threadId );

				var completionsResponse = dap.completions( frame.id, "my" );

				expect( completionsResponse.body ).toHaveKey( "targets" );
				expect( completionsResponse.body.targets.len() ).toBeGT( 0, "Should return completions" );

				cleanupThread( threadId );
			} );

			it( "suggests local variables matching the prefix 'my'", function() {
				if ( !supportsCompletions() ) {
					systemOutput( "skipping: completions not supported", true );
					return;
				}

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
			} );

			it( "suggests struct keys after dot-notation prefix 'myStruct.'", function() {
				if ( !supportsCompletions() ) {
					systemOutput( "skipping: completions not supported", true );
					return;
				}

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
			} );

			it( "suggests nested struct keys after 'myStruct.address.'", function() {
				if ( !supportsCompletions() ) {
					systemOutput( "skipping: completions not supported", true );
					return;
				}

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
			} );

			it( "filters completions by partial input 'myStruct.f'", function() {
				if ( !supportsCompletions() ) {
					systemOutput( "skipping: completions not supported", true );
					return;
				}

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
			} );

			it( "suggests component methods after 'myComponent.'", function() {
				if ( !supportsCompletions() ) {
					systemOutput( "skipping: completions not supported", true );
					return;
				}

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
			} );

			it( "returns completions for empty input (local scope dump)", function() {
				if ( !supportsCompletions() ) {
					systemOutput( "skipping: completions not supported", true );
					return;
				}

				dap.setBreakpoints( variables.targetFile, [ lines.debugLine ] );
				triggerArtifact( "completions-target.cfm" );

				var stopped = dap.waitForEvent( "stopped", 2000 );
				var threadId = stopped.body.threadId;

				var frame = getTopFrame( threadId );

				var completionsResponse = dap.completions( frame.id, "" );

				expect( completionsResponse.body.targets.len() ).toBeGT( 0, "Empty input should return completions" );

				cleanupThread( threadId );
			} );

		} );
	}
}
