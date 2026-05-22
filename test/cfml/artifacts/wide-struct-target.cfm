<cfscript>
/**
 * Target for chunked variables-pagination tests — a struct with enough keys
 * that VSCode's DAP client requests paginated slices via start+count.
 */
function buildWideStruct() {
	var wide = {};
	for ( var i = 1; i lte 500; i++ ) {
		wide[ "key_" & i ] = "value " & i;
	}

	var debugLine = "inspect here";

	return wide;
}

result = buildWideStruct();

writeOutput( "Done: " & structCount( result ) );
</cfscript>
