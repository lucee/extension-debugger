<cfscript>
/**
 * Target for the multi-thread getApplicationSettings cross-bleed test.
 *
 * Two concurrent requests with distinct ?appname= URL params each pause at
 * the breakpoint with their own application context. Tests assert that
 * after interacting with thread A, dap.getApplicationSettings() returns
 * A's app name, not the other concurrent thread's.
 */
appName = application.applicationName;
debugLine = "inspect here";  // breakpoint here
writeOutput( "appSettings-multi: " & appName );
</cfscript>
