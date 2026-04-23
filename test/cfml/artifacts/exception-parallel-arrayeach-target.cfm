<cfscript>
/**
 * Target for exception breakpoint tests — throw inside a parallel arrayEach closure.
 *
 * Parallel arrayEach dispatches the closure across a worker pool and re-throws
 * the first failing invocation on the caller. Whether the uncaught-exception
 * stop fires on a worker thread or the joined main thread is implementation
 * detail — the test only cares that it fires with at least one frame pointing
 * back at this target file.
 */

param name="url.throwException" default="false";

items = [ 1, 2, 3, 4 ];

arrayEach( items, function( item ) {
	if ( url.throwException == "true" && item == 2 ) {
		throw( type="TestException", message="Thrown from parallel arrayEach", detail="parallel arrayEach context" );
	}
}, true, 4 );

writeOutput( "ok" );
</cfscript>
