<cfscript>
// Test script for luceedebug extension deployment
// Run with: profiling\test-extension.bat

function runTest() {
	systemOutput( "============================================================", true );
	systemOutput( "Testing Luceedebug Extension Deployment", true );
	systemOutput( "============================================================", true );
	systemOutput( "", true );

	// Check environment
	systemOutput( "Environment:", true );
	systemOutput( "  LUCEE_DEBUGGER_PORT: " & ( server.system.environment.LUCEE_DEBUGGER_PORT ?: "not set" ), true );
	systemOutput( "  Lucee Version: " & server.lucee.version, true );
	systemOutput( "", true );

	// Check if extension is installed via admin API
	systemOutput( "Checking installed extensions...", true );
	try {
		var admin = new Administrator( "server", "password" );
		var extensions = admin.getExtensions();
		var found = false;
		for ( var ext in extensions ) {
			if ( ext.id contains "DECEB" || ext.name contains "luceedebug" || ext.name contains "Luceedebug" ) {
				systemOutput( "  FOUND: #ext.name# v#ext.version# (id: #ext.id#)", true );
				found = true;
			}
		}
		if ( !found ) {
			systemOutput( "  WARNING: luceedebug extension not found in installed list", true );
			systemOutput( "  Available extensions:", true );
			for ( var ext in extensions ) {
				systemOutput( "    - #ext.name# (#ext.id#)", true );
			}
		}
	} catch ( any e ) {
		systemOutput( "  Could not check extensions via admin: " & e.message, true );
	}
	systemOutput( "", true );

	// Check if DebuggerRegistry exists (Lucee 7.1+)
	systemOutput( "Checking DebuggerRegistry (Lucee 7.1+ native debugging API)...", true );
	try {
		var DebuggerRegistry = createObject( "java", "lucee.runtime.debug.DebuggerRegistry" );
		systemOutput( "  DebuggerRegistry class loaded", true );

		// Try to get the listener
		try {
			var listener = DebuggerRegistry.getListener();
			if ( !isNull( listener ) ) {
				systemOutput( "  Listener registered: " & listener.getClass().getName(), true );
			} else {
				systemOutput( "  No listener registered (null)", true );
			}
		} catch ( any e ) {
			systemOutput( "  Could not get listener: " & e.message, true );
		}
	} catch ( any e ) {
		systemOutput( "  ERROR: DebuggerRegistry not found - requires Lucee 7.1+", true );
		systemOutput( "  " & e.message, true );
	}
	systemOutput( "", true );

	// Simple variable test
	systemOutput( "Testing basic execution...", true );
	var x = 1;
	var y = 2;
	var z = x + y;
	systemOutput( "  x + y = #z# (execution test passed)", true );
	systemOutput( "", true );

	systemOutput( "============================================================", true );
	systemOutput( "Extension test complete", true );
	systemOutput( "============================================================", true );
}

runTest();
</cfscript>
