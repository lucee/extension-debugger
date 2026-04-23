<cfscript>
/**
 * Target for MissingIncludeException — nested variant.
 *
 * This file exists (outer .cfm frame is live) and then includes a template
 * that does NOT exist. The MissingIncludeException is thrown from inside
 * PageSourceImpl.loadPage while the outer _doInclude frame is still on the
 * stack, so the debugger MUST be able to report at least the outer frame.
 */

outerMarker = "nested-missing-include-outer";
</cfscript>
<cfinclude template="this-nested-missing-does-not-exist.cfm">
<cfscript>
writeOutput( "unreached" );
</cfscript>
