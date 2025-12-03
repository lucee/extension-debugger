<cfscript>
// Target script for DAP stepping tests.
// Tests stepIn, stepOver, stepOut by calling nested functions.

function innerFunc( required string value ) {
	var inner1 = "inner: #arguments.value#";  // line 6
	var inner2 = inner1 & "!";                 // line 7
	return inner2;                             // line 8
}

function outerFunc( required string name ) {
	var before = "before";                     // line 12
	var result = innerFunc( arguments.name );  // line 13 - stepIn goes here
	var after = "after: #result#";             // line 14 - stepOver stays here
	return after;                              // line 15
}

// Main execution
var startLine = "start";              // line 19
var output = outerFunc( "test" );     // line 20 - breakpoint here
var endLine = "end: #output#";        // line 21

systemOutput( "dap-step-target.cfm completed: #endLine#", true );
</cfscript>
