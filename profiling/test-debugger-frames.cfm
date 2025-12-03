<cfscript>
// Test script for Lucee's new debugger frame support
// Run with: -Dlucee.debugger.enabled=true

systemOutput( "=== Testing Debugger Frame Support ===" );
systemOutput( "" );

// Check if debugger is enabled
pc = getPageContext();
pci = pc.getClass().getName() == "lucee.runtime.PageContextImpl" ? pc : javaCast( "null", "" );

if ( isNull( pci ) ) {
	systemOutput( "ERROR: Could not get PageContextImpl" );
	abort;
}

// Check the static flag
debuggerEnabled = createObject( "java", "lucee.runtime.PageContextImpl" ).DEBUGGER_ENABLED;
systemOutput( "DEBUGGER_ENABLED: #debuggerEnabled#" );

if ( !debuggerEnabled ) {
	systemOutput( "" );
	systemOutput( "Debugger is DISABLED. Run with -Dlucee.debugger.enabled=true" );
	systemOutput( "" );
	abort;
}

// Test nested function calls
function level3( required string msg ) {
	var localVar = "I am in level3";
	var frames = getPageContext().getDebuggerFrames();

	systemOutput( "" );
	systemOutput( "Inside level3() - #arguments.msg#" );
	systemOutput( "  localVar: #localVar#" );
	systemOutput( "  Frame count: #arrayLen( frames )#" );

	for ( var i = 1; i <= arrayLen( frames ); i++ ) {
		var frame = frames[ i ];
		systemOutput( "  Frame #i#: #frame.functionName# @ #frame.pageSource.getDisplayPath()#" );
		systemOutput( "    - local keys: #structKeyList( frame.local )#" );
		systemOutput( "    - arguments keys: #structKeyList( frame.arguments )#" );
	}

	return localVar;
}

function level2( required numeric num ) {
	var l2Var = "level2 local";
	return level3( "called from level2 with num=#arguments.num#" );
}

function level1() {
	var l1Var = "level1 local";
	var result = level2( 42 );
	return result;
}

// Run the test
systemOutput( "" );
systemOutput( "Calling level1() -> level2() -> level3()..." );
result = level1();

systemOutput( "" );
systemOutput( "Result: #result#" );
systemOutput( "" );
systemOutput( "=== Test Complete ===" );
</cfscript>
