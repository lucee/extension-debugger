<cfscript>
/**
 * Target for cfthread throwOnError test. Spawns a thread that throws, then
 * joins with throwOnError=true so the exception re-throws in the calling thread.
 */

param name="url.throwException" default="false";

thread name="exceptionWorker" shouldThrow="#url.throwException == 'true'#" {
	if ( attributes.shouldThrow ) {
		throw( type="TestException", message="Thrown from cfthread body", detail="cfthread throwOnError context" );
	}
}

thread action="join" name="exceptionWorker" throwOnError=true;

writeOutput( "joined" );
</cfscript>
