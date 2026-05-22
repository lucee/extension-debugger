/**
 * DAP paginated variables expansion.
 *
 * VSCode requests slices of large containers via `start` + `count` on the
 * `variables` request, after seeing high `namedVariables` / `indexedVariables`
 * counts on the parent. The server must honour those bounds and return only
 * the requested slice — otherwise expansion dumps the full container every
 * time the user expands the parent, which is wasteful and unscrollable.
 */
component extends="org.lucee.cfml.test.LuceeTestCase" labels="dap" {

	include "DapTestCase.cfm";

	variables.targetFile = "";

	// Line numbers in artifacts/wide-struct-target.cfm — keep in sync.
	variables.lines = {
		debugLine: 12 // var debugLine = "inspect here";
	};

	function beforeAll() {
		setupDap();
		variables.targetFile = getArtifactPath( "wide-struct-target.cfm" );
	}

	function run( testResults, testBox ) {
		describe( "DAP variables pagination (start + count)", function() {

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

			it( title="parent struct declares namedVariables = total key count", body=function() {
				dap.setBreakpoints( variables.targetFile, [ lines.debugLine ] );
				triggerArtifact( "wide-struct-target.cfm" );

				var stopped = dap.waitForEvent( "stopped", 2000 );
				var threadId = stopped.body.threadId;

				var frame = getTopFrame( threadId );
				var wide = getVariableByName( getScopeByName( frame.id, "Local" ).variablesReference, "wide" );

				expect( wide.namedVariables ).toBe( 500, "parent must declare full child count so VSCode knows to paginate" );

				cleanupThread( threadId );
			}, skip=!isNativeMode() );

			// Red phase: server currently ignores start/count and returns the full
			// 500-key collection regardless of requested slice. With pagination
			// honoured, this should return exactly `count` entries.
			it( title="variables(start=0, count=100) returns first 100 keys only", body=function() {
				dap.setBreakpoints( variables.targetFile, [ lines.debugLine ] );
				triggerArtifact( "wide-struct-target.cfm" );

				var stopped = dap.waitForEvent( "stopped", 2000 );
				var threadId = stopped.body.threadId;

				var frame = getTopFrame( threadId );
				var wide = getVariableByName( getScopeByName( frame.id, "Local" ).variablesReference, "wide" );

				var sliceResponse = dap.getVariables( wide.variablesReference, 0, 100 );
				expect( sliceResponse.body.variables.len() ).toBe( 100, "Page 1 should return exactly 100 keys, got #sliceResponse.body.variables.len()#" );

				cleanupThread( threadId );
			}, skip=!isNativeMode() );

			it( title="variables(start=100, count=100) returns next 100 keys, distinct from page 1", body=function() {
				dap.setBreakpoints( variables.targetFile, [ lines.debugLine ] );
				triggerArtifact( "wide-struct-target.cfm" );

				var stopped = dap.waitForEvent( "stopped", 2000 );
				var threadId = stopped.body.threadId;

				var frame = getTopFrame( threadId );
				var wide = getVariableByName( getScopeByName( frame.id, "Local" ).variablesReference, "wide" );

				var page1 = dap.getVariables( wide.variablesReference, 0, 100 );
				var page2 = dap.getVariables( wide.variablesReference, 100, 100 );

				expect( page2.body.variables.len() ).toBe( 100, "Page 2 should return 100 keys" );

				var page1Names = page1.body.variables.map( function( v ) { return v.name; } );
				var page2Names = page2.body.variables.map( function( v ) { return v.name; } );
				var overlap = page1Names.filter( function( n ) { return page2Names.findNoCase( n ) > 0; } );
				expect( overlap.len() ).toBe( 0, "Page 2 must not overlap page 1; got overlap #serializeJSON( overlap )#" );

				cleanupThread( threadId );
			}, skip=!isNativeMode() );

			it( title="variables(no start/count) still returns the full collection", body=function() {
				dap.setBreakpoints( variables.targetFile, [ lines.debugLine ] );
				triggerArtifact( "wide-struct-target.cfm" );

				var stopped = dap.waitForEvent( "stopped", 2000 );
				var threadId = stopped.body.threadId;

				var frame = getTopFrame( threadId );
				var wide = getVariableByName( getScopeByName( frame.id, "Local" ).variablesReference, "wide" );

				var allResponse = dap.getVariables( wide.variablesReference );
				expect( allResponse.body.variables.len() ).toBe( 500, "Unpaginated request must return all keys" );

				cleanupThread( threadId );
			}, skip=!isNativeMode() );

		} );
	}
}
