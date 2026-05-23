<cfscript>
function testScopes() {
	cookie.testKey = "testCookieValue";
	thread name="testThread" action="run" {
		thread.threadData = "from-thread";
	}
	thread name="testThread" action="join";
	var debugLine = "inspect scopes here";
	return cookie.testKey;
}
result = testScopes();
writeOutput( "Done" );
</cfscript>
