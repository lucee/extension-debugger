<cfscript>
/**
 * Target for multi-thread cross-bleed tests.
 *
 * The URL param `?label=X` becomes a local variable, so two concurrent requests
 * with different labels each have a distinguishable per-request value visible
 * to the debugger. Tests assert that resolving a thread's stale frame id
 * returns THAT request's value, not the other concurrent request's.
 */

function multiThreadProbe( required string label ) {
	var myLabel = arguments.label;
	var myCounter = 0;

	// Breakpoint line — both concurrent requests stop here.
	myCounter = 1;

	// A second instruction so step-over has somewhere to land if needed.
	myCounter = 2;

	return myLabel & ":" & myCounter;
}

label = ( url.label ?: "default" );
result = multiThreadProbe( label );

writeOutput( "Result: " & result );
</cfscript>
