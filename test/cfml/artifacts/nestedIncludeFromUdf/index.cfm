<cfscript>
	function renderView( view ) {
		include template="#arguments.view#";
	}
	renderView( "middle.cfm" );
</cfscript>
