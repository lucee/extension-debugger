<cfscript>
/**
 * Target for exception breakpoint tests — cfrethrow origin.
 *
 * Inner function throws, outer catches and rethrows; nothing else catches,
 * so the rethrown PE escapes the request uncaught.
 */

param name="url.throwException" default="false";

function innerThrower() {
	var innerLocal = "inner-local";
	throw( type="TestException", message="Rethrown test exception", detail="cfrethrow origin" );
}

function outerRethrower() {
	try {
		innerThrower();
	} catch ( any e ) {
		rethrow;
	}
}

if ( url.throwException == "true" ) {
	outerRethrower();
}

writeOutput( "ok" );
</cfscript>
