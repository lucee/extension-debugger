/**
 * Variables-panel scope enumeration: cookie, cfthread, applicationContext.
 *
 * - cookie: always available via pageContext.cookieScope()
 * - cfthread: only appears when at least one thread has been joined
 *   to the current PageContext (aggregated by thread-name)
 * - applicationContext: synthetic scope built from the getApplicationSettings
 *   BIF result struct (snapshot at suspend time)
 */
component extends="org.lucee.cfml.test.LuceeTestCase" labels="dap" {

	include "DapTestCase.cfm";

	variables.targetFile = "";

	// Line in artifacts/scope-enumeration-target.cfm — keep in sync.
	variables.lines = {
		debugLine: 8 // var debugLine = "inspect scopes here";
	};

	function beforeAll() {
		setupDap();
		variables.targetFile = getArtifactPath( "scope-enumeration-target.cfm" );
	}

	function run( testResults, testBox ) {
		describe( "DAP scope enumeration", function() {

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

			it( title="cookie scope exposed with assigned cookie key", body=function() {
				dap.setBreakpoints( variables.targetFile, [ lines.debugLine ] );
				triggerArtifact( "scope-enumeration-target.cfm" );

				var stopped = dap.waitForEvent( "stopped", 2000 );
				var threadId = stopped.body.threadId;

				var frame = getTopFrame( threadId );
				var scopes = dap.scopes( frame.id ).body.scopes;
				var scopeNames = scopes.map( function( s ) { return s.name; } );
				expect( scopeNames ).toInclude( "cookie", "cookie scope should be exposed. Got: #serializeJSON( scopeNames )#" );

				var cookieScope = getScopeByName( frame.id, "cookie" );
				var cookieVars = dap.getVariables( cookieScope.variablesReference ).body.variables;
				var cookieKeys = cookieVars.map( function( v ) { return uCase( v.name ); } );
				expect( cookieKeys ).toInclude( "TESTKEY", "cookie.testKey should appear after assignment. Got: #serializeJSON( cookieKeys )#" );

				cleanupThread( threadId );
			}, skip=!isNativeMode() );

			it( title="cfthread scope exposed and keyed by thread name after join", body=function() {
				dap.setBreakpoints( variables.targetFile, [ lines.debugLine ] );
				triggerArtifact( "scope-enumeration-target.cfm" );

				var stopped = dap.waitForEvent( "stopped", 2000 );
				var threadId = stopped.body.threadId;

				var frame = getTopFrame( threadId );
				var scopes = dap.scopes( frame.id ).body.scopes;
				var scopeNames = scopes.map( function( s ) { return s.name; } );
				expect( scopeNames ).toInclude( "cfthread", "cfthread scope should be exposed after thread join. Got: #serializeJSON( scopeNames )#" );

				var cfthreadScope = getScopeByName( frame.id, "cfthread" );
				var cfthreadVars = dap.getVariables( cfthreadScope.variablesReference ).body.variables;
				var cfthreadKeys = cfthreadVars.map( function( v ) { return uCase( v.name ); } );
				expect( cfthreadKeys ).toInclude( "TESTTHREAD", "cfthread.testThread should appear under thread name. Got: #serializeJSON( cfthreadKeys )#" );

				cleanupThread( threadId );
			}, skip=!isNativeMode() );

			it( title="systemMetrics scope exposed with expected JVM keys", body=function() {
				dap.setBreakpoints( variables.targetFile, [ lines.debugLine ] );
				triggerArtifact( "scope-enumeration-target.cfm" );

				var stopped = dap.waitForEvent( "stopped", 2000 );
				var threadId = stopped.body.threadId;

				var frame = getTopFrame( threadId );
				var scopes = dap.scopes( frame.id ).body.scopes;
				var scopeNames = scopes.map( function( s ) { return s.name; } );
				expect( scopeNames ).toInclude( "systemMetrics", "systemMetrics scope should be exposed. Got: #serializeJSON( scopeNames )#" );

				var sysScope = getScopeByName( frame.id, "systemMetrics" );
				var sysVars = dap.getVariables( sysScope.variablesReference ).body.variables;
				expect( sysVars.len() ).toBeGT( 0, "systemMetrics should expose at least one metric on expand" );

				cleanupThread( threadId );
			}, skip=!isNativeMode() );

			it( title="applicationContext scope exposed with expected setting keys", body=function() {
				dap.setBreakpoints( variables.targetFile, [ lines.debugLine ] );
				triggerArtifact( "scope-enumeration-target.cfm" );

				var stopped = dap.waitForEvent( "stopped", 2000 );
				var threadId = stopped.body.threadId;

				var frame = getTopFrame( threadId );
				var scopes = dap.scopes( frame.id ).body.scopes;
				var scopeNames = scopes.map( function( s ) { return s.name; } );
				expect( scopeNames ).toInclude( "applicationContext", "applicationContext scope should be exposed. Got: #serializeJSON( scopeNames )#" );

				var appCtxScope = getScopeByName( frame.id, "applicationContext" );
				var appCtxVars = dap.getVariables( appCtxScope.variablesReference ).body.variables;
				var appCtxKeys = appCtxVars.map( function( v ) { return v.name; } );
				expect( appCtxKeys ).toInclude( "applicationTimeout", "applicationContext should expose applicationTimeout. Got: #serializeJSON( appCtxKeys )#" );
				expect( appCtxKeys ).toInclude( "datasources", "applicationContext should expose datasources" );
				expect( appCtxKeys ).toInclude( "mappings", "applicationContext should expose mappings" );

				cleanupThread( threadId );
			}, skip=!isNativeMode() );

		} );
	}
}
