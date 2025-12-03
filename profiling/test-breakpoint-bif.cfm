<cfscript>
// Test script for breakpoint() BIF

systemOutput( "=== Testing breakpoint() BIF ===" );
systemOutput( "" );

systemOutput( "isDebuggerEnabled(): #isDebuggerEnabled()#" );

if ( !isDebuggerEnabled() ) {
	systemOutput( "" );
	systemOutput( "Debugger is DISABLED - breakpoint() will be a no-op." );
	systemOutput( "Run with LUCEE_DEBUGGER_ENABLED=true to test suspension." );
	systemOutput( "" );
}

function testFunction( required string name ) {
	var localVar = "Hello, #arguments.name#!";
	systemOutput( "Before breakpoint in testFunction( #arguments.name# )" );

	// Simple breakpoint
	breakpoint();

	systemOutput( "After breakpoint in testFunction( #arguments.name# )" );
	return localVar;
}

function conditionalBreakpointTest( required numeric value ) {
	systemOutput( "Testing conditional breakpoint with value=#arguments.value#" );

	// Only break when value > 5
	breakpoint( arguments.value > 5, "value > 5 breakpoint" );

	return arguments.value * 2;
}

// Test simple breakpoint
systemOutput( "" );
systemOutput( "--- Test 1: Simple breakpoint ---" );
result = testFunction( "World" );
systemOutput( "Result: #result#" );

// Test conditional breakpoint (should NOT suspend)
systemOutput( "" );
systemOutput( "--- Test 2: Conditional breakpoint (value=3, should NOT suspend) ---" );
result = conditionalBreakpointTest( 3 );
systemOutput( "Result: #result#" );

// Test conditional breakpoint (SHOULD suspend)
systemOutput( "" );
systemOutput( "--- Test 3: Conditional breakpoint (value=10, SHOULD suspend) ---" );
result = conditionalBreakpointTest( 10 );
systemOutput( "Result: #result#" );

systemOutput( "" );
systemOutput( "=== Test Complete ===" );
</cfscript>
