/**
 * Uncaught-exception breakpoints — throw-origin coverage.
 *
 * Holds the execution context constant (UDF-in-cfm via exception-target.cfm)
 * and varies how the exception is produced. Each case asserts the debugger
 * can report ≥2 frames and inspect the throwing function's scope.
 */
component extends="org.lucee.cfml.test.LuceeTestCase" labels="dap" {

	include "DapTestCase.cfm";

	variables.targetFile = "";

	function beforeAll() {
		setupDap();
		variables.targetFile = getArtifactPath( "exception-target.cfm" );
	}

	function run( testResults, testBox ) {
		describe( "DAP exception origins", function() {

			beforeEach( function() {
				dap.drainEvents();
			} );

			afterEach( function() {
				dap.setExceptionBreakpoints( [] );
				clearBreakpoints( variables.targetFile );

				for ( var threadId in dap.getSuspendedThreadIds() ) {
					try {
						dap.continueThread( threadId );
					} catch ( any e ) {
						systemOutput( "afterEach: continue thread #threadId# ignored: #e.message#", true );
					}
				}

				try {
					waitForHttpComplete( 3000 );
				} catch ( any e ) {
					systemOutput( "afterEach: http drain timeout ignored: #e.message#", true );
				}

				dap.drainEvents();
			} );

			it( "cfthrow message= (no type) stops with frames intact", function() {
				if ( !supportsExceptionBreakpoints() ) {
					systemOutput( "skipping: exception breakpoints not supported", true );
					return;
				}

				dap.setExceptionBreakpoints( [ "uncaught" ] );
				triggerArtifact( "exception-target.cfm", { throwException: true, catchException: false, throwMode: "message" }, true );

				var stopped = dap.waitForEvent( "stopped", 2000 );
				expect( stopped.body.reason ).toBe( "exception" );
				var threadId = stopped.body.threadId;

				var frames = dap.stackTrace( threadId ).body.stackFrames;
				expect( frames.len() ).toBeGTE( 2, "cfthrow message= should expose ≥2 frames" );
				expect( frames[ 1 ].name ).toInclude( "riskyFunction" );

				var args = getScopeByName( frames[ 1 ].id, "Arguments" );
				var shouldThrow = getVariableByName( args.variablesReference, "shouldThrow" );
				expect( shouldThrow.value.lcase() ).toBe( "true" );

				cleanupThread( threadId );
			} );

			it( "cfthrow object= (rethrow) stops with frames intact", function() {
				if ( !supportsExceptionBreakpoints() ) {
					systemOutput( "skipping: exception breakpoints not supported", true );
					return;
				}

				dap.setExceptionBreakpoints( [ "uncaught" ] );
				triggerArtifact( "exception-target.cfm", { throwException: true, catchException: false, throwMode: "object" }, true );

				var stopped = dap.waitForEvent( "stopped", 2000 );
				expect( stopped.body.reason ).toBe( "exception" );
				var threadId = stopped.body.threadId;

				var frames = dap.stackTrace( threadId ).body.stackFrames;
				expect( frames.len() ).toBeGTE( 2, "cfthrow object= should expose ≥2 frames" );
				expect( frames[ 1 ].name ).toInclude( "riskyFunction" );

				cleanupThread( threadId );
			} );

			it( "CasterException (int('abc')) stops with frames intact", function() {
				if ( !supportsExceptionBreakpoints() ) {
					systemOutput( "skipping: exception breakpoints not supported", true );
					return;
				}

				dap.setExceptionBreakpoints( [ "uncaught" ] );
				triggerArtifact( "exception-target.cfm", { throwException: true, catchException: false, throwMode: "caster" }, true );

				var stopped = dap.waitForEvent( "stopped", 2000 );
				expect( stopped.body.reason ).toBe( "exception" );
				var threadId = stopped.body.threadId;

				var frames = dap.stackTrace( threadId ).body.stackFrames;
				expect( frames.len() ).toBeGTE( 2, "CasterException should expose ≥2 frames" );
				expect( frames[ 1 ].name ).toInclude( "riskyFunction" );

				cleanupThread( threadId );
			} );

			it( "UndefinedImpl (missing variable) stops with frames intact", function() {
				if ( !supportsExceptionBreakpoints() ) {
					systemOutput( "skipping: exception breakpoints not supported", true );
					return;
				}

				dap.setExceptionBreakpoints( [ "uncaught" ] );
				triggerArtifact( "exception-target.cfm", { throwException: true, catchException: false, throwMode: "undefined" }, true );

				var stopped = dap.waitForEvent( "stopped", 2000 );
				expect( stopped.body.reason ).toBe( "exception" );
				var threadId = stopped.body.threadId;

				var frames = dap.stackTrace( threadId ).body.stackFrames;
				expect( frames.len() ).toBeGTE( 2, "Undefined-variable exception should expose ≥2 frames" );
				expect( frames[ 1 ].name ).toInclude( "riskyFunction" );

				cleanupThread( threadId );
			} );

			it( "cfrethrow in catch stops exactly once with frames intact", function() {
				if ( !supportsExceptionBreakpoints() ) {
					systemOutput( "skipping: exception breakpoints not supported", true );
					return;
				}

				dap.setExceptionBreakpoints( [ "uncaught" ] );
				triggerArtifact( "exception-rethrow-target.cfm", { throwException: true }, true );

				var first = dap.waitForEvent( "stopped", 2000 );
				expect( first.body.reason ).toBe( "exception" );
				var threadId = first.body.threadId;

				var frames = dap.stackTrace( threadId ).body.stackFrames;
				expect( frames.len() ).toBeGTE( 2, "rethrow should expose ≥2 frames (throwing UDF + include)" );
				expect( frames[ 1 ].name ).toInclude( "innerThrower" );

				// PE-marker dedup: rethrow reuses the same PE, so no second stopped event.
				sleep( 500 );
				var events = dap.drainEvents();
				var extraStops = 0;
				for ( var event in events ) {
					if ( event.event == "stopped" && ( event.body.reason ?: "" ) == "exception" ) {
						extraStops++;
					}
				}
				expect( extraStops ).toBe( 0, "rethrow of already-notified PE should not fire a second stopped event" );

				cleanupThread( threadId );
			} );

			it( "UDFCasterException (bad return type) stops with frames intact", function() {
				if ( !supportsExceptionBreakpoints() ) {
					systemOutput( "skipping: exception breakpoints not supported", true );
					return;
				}

				dap.setExceptionBreakpoints( [ "uncaught" ] );
				triggerArtifact( "exception-target.cfm", { throwException: true, catchException: false, throwMode: "udfCaster" }, true );

				var stopped = dap.waitForEvent( "stopped", 2000 );
				expect( stopped.body.reason ).toBe( "exception" );
				var threadId = stopped.body.threadId;

				var frames = dap.stackTrace( threadId ).body.stackFrames;
				expect( frames.len() ).toBeGTE( 3, "UDF return-type cast should expose ≥3 frames (typedReturn + riskyFunction + include)" );
				expect( frames[ 1 ].name ).toInclude( "typedReturn" );

				cleanupThread( threadId );
			} );

		} );
	}
}
