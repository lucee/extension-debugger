component {

	function throwFromMethod( required boolean shouldThrow ) {
		var methodLocal = "method-local";
		if ( arguments.shouldThrow ) {
			throw( type="TestException", message="Thrown from component method", detail="component context" );
		}
		return "ok";
	}

}
