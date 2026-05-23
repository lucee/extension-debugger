<cfscript>
/**
 * Target for the cross-frame pin survival test.
 *
 * Recursive call chain creates a deep stack where each frame holds its own
 * RichComponent instance. The test walks every frame, expanding the CFC
 * (which registers MarkerTrait.Scope / PreBuiltGroup pins per frame), then
 * scrolls back up and re-expands the oldest frame's saved variablesReference.
 *
 * Under the legacy 50-entry LRU the older frame's scope markers get evicted
 * once total pin pressure exceeds the cap (~3-4 frames worth of churn) and
 * the panel goes blank. Per-frame pinning keeps every frame's markers
 * strongly referenced until the frame resumes.
 */
function frameDeep( required numeric depth ) {
	var myCfc = new RichComponent();
	var localValue = "frame-" & arguments.depth;
	if ( arguments.depth > 1 ) {
		return frameDeep( arguments.depth - 1 );
	}
	// Breakpoint here — bottom of recursion, ~8 frames deep including the
	// outermost cfm entry frame.
	var breakpointMarker = "stop";
	return myCfc;
}

result = frameDeep( 8 );

writeOutput( "Done" );
</cfscript>
