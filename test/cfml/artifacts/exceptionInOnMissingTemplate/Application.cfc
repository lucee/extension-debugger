component {

	this.name = "exception-in-on-missing-template";

	function onMissingTemplate( targetPage ) {
		if ( ( url.mode ?: "clean" ) == "throw" ) {
			throw( type="TestException", message="onMissingTemplate threw", detail="onMissingTemplate test" );
		}
		writeOutput( "handled: " & arguments.targetPage );
		return true;
	}

}
