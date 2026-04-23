<cfscript>
/**
 * Target for request-timeout exception-breakpoint filter test.
 *
 * RequestTimeoutException is NOT silent (Abort.isSilentAbort returns false
 * for it), so it MUST fire the uncaught-exception breakpoint.
 */

setting requesttimeout=1;
sleep( 3000 );

writeOutput( "unreached" );
</cfscript>
