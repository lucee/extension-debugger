<cfscript>
/**
 * Target file for exception breakpoint tests.
 *
 * Tests breaking on uncaught exceptions.
 */

param name="url.throwException" default="false";
param name="url.catchException" default="false";
param name="url.throwMode" default="type";

function riskyFunction( required boolean shouldThrow ) {
	var localMarker = "risky-local";
	if ( arguments.shouldThrow ) {
		switch ( url.throwMode ) {
			case "type":
				throw( type="TestException", message="Intentional test exception", detail="This is for testing" );
			case "message":
				throw( message="Intentional test exception" );
			case "object":
				try {
					throw( type="InnerException", message="Intentional test exception" );
				} catch ( any inner ) {
					throw( object=inner );
				}
			case "caster":
				return int( "not-a-number" );
			case "undefined":
				return writeOutput( noSuchVariableAnywhere );
			case "udfCaster":
				return typedReturn();
			default:
				throw( type="TestException", message="Intentional test exception", detail="This is for testing" );
		}
	}
	return "success";
}

numeric function typedReturn() {
	return "definitely-not-numeric";
}

function wrapperFunction( required boolean shouldThrow, required boolean shouldCatch ) {
	if ( arguments.shouldCatch ) {
		try {
			return riskyFunction( arguments.shouldThrow );
		} catch ( any e ) {
			return "caught: " & e.message;
		}
	} else {
		return riskyFunction( arguments.shouldThrow );
	}
}

result = wrapperFunction(
	shouldThrow = url.throwException == "true",
	shouldCatch = url.catchException == "true"
);

writeOutput( "Result: #result#" );
</cfscript>
