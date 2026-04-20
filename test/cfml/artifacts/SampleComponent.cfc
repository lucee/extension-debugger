component accessors="true" hint="used in MetadataTest" {

	property name="foo" type="string";

	public string function greet( required string who ) {
		return "hello " & arguments.who;
	}

}
