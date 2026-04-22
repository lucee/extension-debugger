<cfscript>
/**
 * Target for catch-body line breakpoint tests.
 *
 * Line layout (keep in sync with ExceptionBreakpointsTest.cfc):
 *   catchBodyLine: line with `caughtMessage = e.message;`
 *   rethrowLine:   line with `rethrow;`
 */

param name="url.rethrow" default="false";

function riskyFunction() {
	throw( type="TestException", message="Intentional test exception", detail="catch-body test" );
}

function caller() {
	try {
		riskyFunction();
	} catch ( any e ) {
		caughtMessage = e.message;                    // catchBodyLine
		if ( url.rethrow == "true" ) {
			rethrow;                                  // rethrowLine
		}
		return "caught: " & e.message;
	}
	return "unreachable";
}

result = caller();
writeOutput( "Result: #result#" );
</cfscript>
