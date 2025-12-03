<cfscript>
// Simple target script for DAP testing.
// Set a breakpoint on the line inside testFunc to test debugging.

function testFunc( required string name ) {
	var greeting = "Hello, #arguments.name#!";  // <- set breakpoint here (line 7)
	var timestamp = now();
	return greeting;
}

result = testFunc( "World" );

systemOutput( "dap-target.cfm completed: #result#", true );
</cfscript>
