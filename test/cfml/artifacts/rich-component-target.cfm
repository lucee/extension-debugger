<cfscript>
/**
 * Target file for the rich-CFC sub-group rendering tests.
 * Uses RichComponent so every Variables-panel sub-group has non-empty content.
 */
function testRichComponent() {
	var richComponent = new RichComponent();

	var debugLine = "inspect here";

	return richComponent;
}

result = testRichComponent();

writeOutput( "Done" );
</cfscript>
