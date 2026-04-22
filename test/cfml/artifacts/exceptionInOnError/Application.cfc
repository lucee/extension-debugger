component {

	this.name = "exception-in-on-error";

	function onError( exception, event ) {
		var errorMessage = arguments.exception.message;      // onErrorLine
		writeOutput( "handled: " & errorMessage );
	}

}
