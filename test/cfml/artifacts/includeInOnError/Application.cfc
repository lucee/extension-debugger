component {
	this.name="include-in-on-error";

	function onError( exception, event ){
		include template="error.cfm";
	}
}
