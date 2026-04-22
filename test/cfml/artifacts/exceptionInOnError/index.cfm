<cfscript>
/**
 * Target for onError line-breakpoint tests.
 *
 * Throws an uncaught exception so Application.cfc onError runs.
 */
throw( type="TestException", message="Intentional for onError", detail="onError test" );
</cfscript>
