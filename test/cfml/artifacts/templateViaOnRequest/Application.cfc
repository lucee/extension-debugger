component {
	this.name="template-via-on-request";

	function onRequest( targetPage ){
		include template="#arguments.targetPage#";
		abort;
	}
}