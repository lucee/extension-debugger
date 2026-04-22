<cfscript>
	function renderView( view ){
		include template="#arguments.view#";
	}
	renderView( "inner.cfm" );
</cfscript>
