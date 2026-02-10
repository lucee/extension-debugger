<cfscript>
	systemOutput("Request: " & cgi.request_url, true);
	greeting = "Hello from Lucee!";
	now = now();
</cfscript>
<cfoutput>
	<h1>#greeting#</h1>
	<p>#dateTimeFormat( now, "full" )#</p>
</cfoutput>
