<cfscript>
// Target for GetApplicationSettingsTest.
// Application.cfc in this dir sets known this.* values the test asserts against.
appName = application.applicationName;
debugLine = "inspect here";
writeOutput( "appSettings: " & appName );
</cfscript>
