<cfscript>
	if ( thisTag.executionMode == "end" ) exit "exitTag";
	variables.moduleVar = "module-only";
	debugMarker = "stop here"; // line 4 — debugLine
	echo( "widget" );
</cfscript>
