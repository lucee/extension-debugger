<cfscript>
/**
 * Target for silent-abort exception-breakpoint filter tests.
 *
 * Both modes trigger Abort-family throws that are in the `isSilentAbort`
 * set and must NOT fire the uncaught-exception breakpoint.
 *
 *   url.mode=abort   → <cfabort>
 *   url.mode=content → <cfcontent file=...>  (PostContentAbort)
 */

param name="url.mode" default="abort";

switch ( url.mode ) {
	case "abort":
		abort;
	case "content":
		cfcontent( type="text/plain", file=getDirectoryFromPath( getCurrentTemplatePath() ) & "silent-fixture.txt" );
}

writeOutput( "unreached" );
</cfscript>
