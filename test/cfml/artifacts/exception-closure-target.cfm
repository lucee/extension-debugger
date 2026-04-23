<cfscript>
/**
 * Target for exception breakpoint tests — closure-body throw.
 */

param name="url.throwException" default="false";

runner = function( required boolean shouldThrow ) {
	var closureLocal = "closure-local";
	if ( arguments.shouldThrow ) {
		throw( type="TestException", message="Thrown from closure", detail="closure context" );
	}
	return "ok";
};

result = runner( url.throwException == "true" );
writeOutput( "Result: #result#" );
</cfscript>
