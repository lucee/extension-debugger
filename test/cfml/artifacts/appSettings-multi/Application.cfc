component {
	// URL-driven name produces a distinct application context per request, so
	// two concurrent requests with different ?appname= params end up in
	// different Application.cfc instances simultaneously.
	this.name = url.appname ?: "appSettings-multi-default";
	this.sessionManagement = false;
	this.setClientCookies = false;
	this.applicationTimeout = createTimespan( 0, 1, 0, 0 );
}
