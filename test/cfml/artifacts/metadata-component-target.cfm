<cfscript>
/**
 * Target file for CFC-instance metadata tests.
 * Isolated so a CFC in the scope doesn't interfere with variables-target.cfm tests.
 */
function testComponentMetadata() {
	var localComponent = new SampleComponent();

	var debugLine = "inspect here";

	return localComponent;
}

result = testComponentMetadata();

writeOutput( "Done" );
</cfscript>
