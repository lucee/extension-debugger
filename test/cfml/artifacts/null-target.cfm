<cfscript>
/**
 * Target file for null-handling tests.
 *
 * Covers:
 * - null-valued struct key (localStruct.nullField)
 * - null local variable (localNull)
 * - scope dump / struct dump walking null entries without crashing
 */
function testNulls() {
	var localString = "hello";
	var localStruct = {
		"name": "test",
		"value": 123,
		"nullField": nullValue()
	};
	var localNull = nullValue();

	var debugLine = "inspect here";

	return localString;
}

result = testNulls();

writeOutput( "Done: " & result );
</cfscript>
