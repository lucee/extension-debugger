<cfscript>
/**
 * Target for exception breakpoint tests — outer cftry with NON-matching type.
 *
 * Throws TestException but the surrounding cftry only catches NeverMatches,
 * so the exception propagates through and ends up uncaught. Useful for
 * probing whether the debugger fires multiple `stopped` events (setCatch
 * signal=true path + execute() top-level catch).
 */

param name="url.throwException" default="false";

function innerThrower( required boolean shouldThrow ) {
	if ( arguments.shouldThrow ) {
		throw( type="TestException", message="Not caught by outer try", detail="outer catches NeverMatches only" );
	}
	return "ok";
}

try {
	result = innerThrower( url.throwException == "true" );
} catch ( NeverMatches e ) {
	result = "impossibly caught";
}

writeOutput( "Result: #result#" );
</cfscript>
