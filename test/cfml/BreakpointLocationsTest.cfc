/**
 * Tests for breakpointLocations request (valid breakpoint lines in a file).
 *
 * This is a native-only feature that uses Page.getExecutableLines() from Lucee core.
 *
 * BDD style — runtime `isNativeMode()` guard inside each `it` (not `skip=`,
 * see DelayedVerifyTest.cfc:44-48 and feedback_testbox_style memory).
 */
component extends="org.lucee.cfml.test.LuceeTestCase" labels="dap" {

	include "DapTestCase.cfm";

	variables.targetFile = "";

	function beforeAll() {
		setupDap();
		variables.targetFile = getArtifactPath( "breakpoint-target.cfm" );
	}

	function afterAll() {
		teardownDap();
	}

	function run( testResults, testBox ) {
		describe( "DAP breakpointLocations", function() {

			beforeEach( function() {
				dap.drainEvents();
			} );

			it( "returns a breakpoints array for a single starting line", function() {
				if ( !supportsBreakpointLocations() ) {
					systemOutput( "skipping: breakpointLocations not supported", true );
					return;
				}

				var response = dap.breakpointLocations( variables.targetFile, 1 );

				expect( response.body ).toHaveKey( "breakpoints" );
				expect( response.body.breakpoints ).toBeArray();
			} );

			it( "reports a known executable line (line 12 inside simpleFunction)", function() {
				if ( !supportsBreakpointLocations() ) {
					systemOutput( "skipping: breakpointLocations not supported", true );
					return;
				}

				var response = dap.breakpointLocations( variables.targetFile, 12 );

				expect( response.body.breakpoints.len() ).toBeGTE( 1, "Line 12 should be executable" );

				var location = response.body.breakpoints[ 1 ];
				expect( location.line ).toBe( 12 );
			} );

			it( "constrains results to the requested range (10-20)", function() {
				if ( !supportsBreakpointLocations() ) {
					systemOutput( "skipping: breakpointLocations not supported", true );
					return;
				}

				var response = dap.breakpointLocations( variables.targetFile, 10, 20 );

				expect( response.body.breakpoints.len() ).toBeGT( 1, "Should have multiple executable lines in range" );

				for ( var loc in response.body.breakpoints ) {
					expect( loc.line ).toBeGTE( 10, "Line should be >= 10" );
					expect( loc.line ).toBeLTE( 20, "Line should be <= 20" );
				}
			} );

			it( "does not mark a comment line as directly executable", function() {
				if ( !supportsBreakpointLocations() ) {
					systemOutput( "skipping: breakpointLocations not supported", true );
					return;
				}

				// Line 3 is a comment. Either empty result or adjusted to a
				// different line, but never line 3 itself.
				var response = dap.breakpointLocations( variables.targetFile, 3, 3 );

				if ( response.body.breakpoints.len() > 0 ) {
					expect( response.body.breakpoints[ 1 ].line ).notToBe( 3, "Comment line should not be directly executable" );
				}
			} );

			it( "does not error on a blank-or-trailing line (line 28)", function() {
				if ( !supportsBreakpointLocations() ) {
					systemOutput( "skipping: breakpointLocations not supported", true );
					return;
				}

				var response = dap.breakpointLocations( variables.targetFile, 28, 28 );
				expect( response.body ).toHaveKey( "breakpoints" );
			} );

			it( "every returned location can be bound as a verified breakpoint", function() {
				if ( !supportsBreakpointLocations() ) {
					systemOutput( "skipping: breakpointLocations not supported", true );
					return;
				}

				var response = dap.breakpointLocations( variables.targetFile, 1, 50 );

				for ( var loc in response.body.breakpoints ) {
					var bpResponse = dap.setBreakpoints( variables.targetFile, [ loc.line ] );
					expect( bpResponse.body.breakpoints[ 1 ].verified ).toBeTrue(
						"Breakpoint at line #loc.line# should be verified"
					);
				}

				// Clean up all breakpoints bound above.
				dap.setBreakpoints( variables.targetFile, [] );
			} );

			it( "reports executable lines inside stepping-target.cfm's inner + outer funcs", function() {
				if ( !supportsBreakpointLocations() ) {
					systemOutput( "skipping: breakpointLocations not supported", true );
					return;
				}

				var steppingFile = getArtifactPath( "stepping-target.cfm" );
				var response = dap.breakpointLocations( steppingFile, 1, 30 );

				expect( response.body.breakpoints.len() ).toBeGT( 0, "Should have executable lines" );

				var lines = response.body.breakpoints.map( function( loc ) { return loc.line; } );
				// stepping-target.cfm: line 9 = `var doubled = arguments.x * 2;` inside innerFunc.
				// line 15 = `var result = innerFunc( intermediate );` inside outerFunc.
				// (Prior test asserted 12 + 17 — those are a blank line and a closing brace;
				//  the test was silently skipping, so the stale expectation went unnoticed.)
				expect( lines ).toInclude( 9, "Line 9 (var doubled) inside innerFunc should be executable" );
				expect( lines ).toInclude( 15, "Line 15 (innerFunc call) inside outerFunc should be executable" );
			} );

			it( "reports line 35 of variables-target.cfm as executable (debugLine)", function() {
				if ( !supportsBreakpointLocations() ) {
					systemOutput( "skipping: breakpointLocations not supported", true );
					return;
				}

				var variablesFile = getArtifactPath( "variables-target.cfm" );
				var response = dap.breakpointLocations( variablesFile, 1, 50 );

				expect( response.body.breakpoints.len() ).toBeGT( 0, "Should have executable lines" );

				var lines = response.body.breakpoints.map( function( loc ) { return loc.line; } );
				expect( lines ).toInclude( 35, "Line 35 should be executable" );
			} );

		} );
	}
}
