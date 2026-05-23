component accessors="true" hint="used in ComponentVariablesTest — non-empty in every sub-group" {

	property name="alpha" type="string";
	property name="beta" type="numeric" getter="false";
	property name="gamma" type="boolean" setter="false";

	static {
		static.staticCounter = 42;
		static.staticLabel = "shared";
	}

	function init() {
		this.publicData = "hello";
		variables.privateData = "secret";
		return this;
	}

	public string function doStuff( required string name, numeric count=1, boolean flag ) {
		return arguments.name & arguments.count & arguments.flag;
	}

	private function helper() {
		return "internal";
	}

	package function pkgFn( string label ) {
		return arguments.label;
	}
}
