<cfscript>
/**
 * Target for exception breakpoint tests — throw inside cfthread.
 */

param name="url.throwException" default="false";

thread name="exceptionWorker" shouldThrow="#url.throwException == 'true'#" {
	var threadLocal = "thread-local";
	if ( attributes.shouldThrow ) {
		throw( type="TestException", message="Thrown from cfthread", detail="cfthread context" );
	}
}

// Don't join — let the thread throw asynchronously.
writeOutput( "spawned" );
</cfscript>
