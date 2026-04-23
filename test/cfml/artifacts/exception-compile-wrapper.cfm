<cfscript>
/**
 * Wrapper for nested-compile-error test. Includes a sibling file that has
 * an intentional syntax error; the resulting TemplateException must fire
 * the uncaught-exception breakpoint because this wrapper's frame is live.
 */
writeOutput( "before include" );
include "exception-compile-broken.cfm";
writeOutput( "after include (unreached)" );
</cfscript>
