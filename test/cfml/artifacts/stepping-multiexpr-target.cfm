<cfset var1 = "a">
<cfset var2 = "b">
<cfset var3 = var1 & var2>
<cfset var4 = var3 & var1>
<cfoutput>done: #var4#</cfoutput>
