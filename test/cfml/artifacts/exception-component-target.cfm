<cfscript>
/**
 * Target for exception breakpoint tests — component-method throw.
 */

param name="url.throwException" default="false";

thrower = new ExceptionThrower();
result = thrower.throwFromMethod( shouldThrow = url.throwException == "true" );

writeOutput( "Result: #result#" );
</cfscript>
