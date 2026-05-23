<cfscript>
/**
 * Target for the pin lifetime invariant test.
 *
 * Builds a single frame holding many distinct RichComponent instances.
 * The test expands every one in sequence (registering MarkerTrait.Scope
 * / PreBuiltGroup pins per expansion), forces GC, then re-walks the saved
 * variablesReferences expecting all of them to still resolve.
 *
 * Under the legacy 50-entry LRU the earliest expansions get evicted once
 * the cap is exceeded — re-expanding them returns empty. Per-frame
 * pinning keeps the whole batch alive until the frame resumes.
 */
function inspectManyCfcs() {
	var cfcs = [];
	var i = 1;
	for ( i = 1; i <= 60; i++ ) {
		cfcs[ i ] = new RichComponent();
	}
	// Breakpoint here — single frame with 60 distinct CFC locals.
	var breakpointMarker = "stop";
	return cfcs;
}

result = inspectManyCfcs();

writeOutput( "Done" );
</cfscript>
