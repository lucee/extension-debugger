component {
	this.name="include-in-on-request";

	function onRequest( targetPage ){
		include template="#arguments.targetPage#";
	}
}
