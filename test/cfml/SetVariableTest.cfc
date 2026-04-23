/**
 * Tests for setVariable functionality (modifying variables at runtime).
 *
 * BDD style — skip= uses capabilities probed at include-time via DapTestCase.cfm.
 */
component extends="org.lucee.cfml.test.LuceeTestCase" labels="dap" {

	include "DapTestCase.cfm";

	variables.targetFile = "";

	// Line numbers in set-variable-target.cfm — keep in sync with the file.
	variables.lines = {
		checkpoint1: 15,  // var checkpoint1 = true;
		checkpoint2: 21   // var checkpoint2 = true;
	};

	function beforeAll() {
		setupDap();
		variables.targetFile = getArtifactPath( "set-variable-target.cfm" );
	}

	function run( testResults, testBox ) {
		describe( "DAP setVariable", function() {

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

			it( title="native: checkpoint lines are valid breakpoint locations", body=function() {
				var locations = dap.breakpointLocations( variables.targetFile, 1, 30 );
				var validLines = locations.body.breakpoints.map( function( bp ) { return bp.line; } );

				systemOutput( "#variables.targetFile# valid lines: #serializeJSON( validLines )#", true );

				for ( var key in variables.lines ) {
					var line = variables.lines[ key ];
					expect( validLines ).toInclude( line, "#variables.targetFile# line #line# (#key#) should be a valid breakpoint location" );
				}
			}, skip=notSupportsBreakpointLocations() );

			it( title="modifies a local string variable and the new value is visible on re-read", body=function() {
				dap.setBreakpoints( variables.targetFile, [ lines.checkpoint1 ] );
				triggerArtifact( "set-variable-target.cfm" );

				var stopped = dap.waitForEvent( "stopped", 2000 );
				var threadId = stopped.body.threadId;

				var frame = getTopFrame( threadId );
				var localScope = getScopeByName( frame.id, "Local" );

				var modifiable = getVariableByName( localScope.variablesReference, "modifiable" );
				expect( modifiable.value ).toBe( '"original"' );

				var setResponse = dap.setVariable( localScope.variablesReference, "modifiable", '"modified"' );
				expect( setResponse.body.value ).toBe( '"modified"' );

				var updatedVar = getVariableByName( localScope.variablesReference, "modifiable" );
				expect( updatedVar.value ).toBe( '"modified"' );

				cleanupThread( threadId );
			}, skip=notSupportsSetVariable() );

			it( title="modifies a local numeric variable", body=function() {
				dap.setBreakpoints( variables.targetFile, [ lines.checkpoint1 ] );
				triggerArtifact( "set-variable-target.cfm" );

				var stopped = dap.waitForEvent( "stopped", 2000 );
				var threadId = stopped.body.threadId;

				var frame = getTopFrame( threadId );
				var localScope = getScopeByName( frame.id, "Local" );

				var numericVar = getVariableByName( localScope.variablesReference, "numericVar" );
				expect( numericVar.value ).toBe( "100" );

				var setResponse = dap.setVariable( localScope.variablesReference, "numericVar", "999" );
				expect( setResponse.body.value ).toBe( "999" );

				cleanupThread( threadId );
			}, skip=notSupportsSetVariable() );

			it( title="modified values are observable by subsequent execution (to the next breakpoint)", body=function() {
				dap.setBreakpoints( variables.targetFile, [ lines.checkpoint1, lines.checkpoint2 ] );
				triggerArtifact( "set-variable-target.cfm" );

				var stopped = dap.waitForEvent( "stopped", 2000 );
				var threadId = stopped.body.threadId;

				var frame = getTopFrame( threadId );
				var localScope = getScopeByName( frame.id, "Local" );

				dap.setVariable( localScope.variablesReference, "modifiable", '"CHANGED"' );
				dap.setVariable( localScope.variablesReference, "numericVar", "555" );

				dap.continueThread( threadId );
				stopped = dap.waitForEvent( "stopped", 2000 );
				threadId = stopped.body.threadId;

				frame = getTopFrame( threadId );
				localScope = getScopeByName( frame.id, "Local" );

				var result = getVariableByName( localScope.variablesReference, "result" );
				// result = modifiable & " - " & numericVar = "CHANGED - 555"
				expect( result.value ).toBe( '"CHANGED - 555"' );

				cleanupThread( threadId );
			}, skip=notSupportsSetVariable() );

			it( title="modifies a boolean variable", body=function() {
				dap.setBreakpoints( variables.targetFile, [ lines.checkpoint1 ] );
				triggerArtifact( "set-variable-target.cfm" );

				var stopped = dap.waitForEvent( "stopped", 2000 );
				var threadId = stopped.body.threadId;

				var frame = getTopFrame( threadId );
				var localScope = getScopeByName( frame.id, "Local" );

				// booleanVar is assigned before the checkpoint1 breakpoint line, so it
				// exists in local scope when native stops AT that line. `checkpoint1`
				// itself can't be used — native breaks before the assignment runs.
				var boolVar = getVariableByName( localScope.variablesReference, "booleanVar" );
				expect( boolVar.value.lcase() ).toBe( "true" );

				var setResponse = dap.setVariable( localScope.variablesReference, "booleanVar", "false" );
				expect( setResponse.body.value.lcase() ).toBe( "false" );

				cleanupThread( threadId );
			}, skip=notSupportsSetVariable() );

		} );
	}
}
