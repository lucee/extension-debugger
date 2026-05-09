<cfscript>
/**
 * Target file for self-referential struct inspection (LDEV-6309).
 *
 * Repros the StackOverflowError when the debugger registers a struct
 * containing itself in ValTracker.wrapperByObj.
 */

function testCircular() {
	var circular = {};
	circular.self = circular;

	var indirectA = {};
	var indirectB = {};
	indirectA.b = indirectB;
	indirectB.a = indirectA;

	var debugLine = "inspect here";

	return circular;
}

testCircular();

writeOutput( "Done" );
</cfscript>
