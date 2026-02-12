<cfscript>

	deploy = directoryList("/opt/lucee/server/lucee-server/deploy/");
	dump(deploy);
	flush;

	systemOutput("Request: " & cgi.request_url, true);
	greeting = "Hello from Lucee!";
	now = now();
	

	systemOutput("Triggering breakpoint via BIF", true);
	breakpoint();
</cfscript>
<cfoutput>
	<h1>#greeting#</h1>
	<p>#dateTimeFormat( now, "full" )#</p>
	
</cfoutput>
<cfscript>

	systemOutput("Triggering breakpoint via throw", true);

	function throwWithStack(){
		throw("zac");
	}

	throwWithStack();
</cfscript>