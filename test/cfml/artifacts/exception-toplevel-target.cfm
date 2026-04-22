<cfscript>
/**
 * Target for exception breakpoint tests — top-level .cfm throw (no UDF).
 */

param name="url.throwException" default="false";

if ( url.throwException == "true" ) {
	topLevelMarker = "top-level-local";
	throw( type="TestException", message="Top-level throw", detail="no UDF wrapping" );
}

writeOutput( "ok" );
</cfscript>
