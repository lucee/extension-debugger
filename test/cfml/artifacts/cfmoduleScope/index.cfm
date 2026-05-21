<cfscript>
	variables.callerVar = "caller-only";
	cfmodule( template="widget.cfm" );
	echo( "ok #variables.callerVar#" );
</cfscript>
