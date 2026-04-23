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

			// Probes whether cfcatch subclass fields (detail, errorCode, extendedInfo) are
			// populated at the uncaught-exception stop. A notify fired inside
			// PageExceptionImpl's base constructor would see an empty detail (the
			// CustomTypeException subclass ctor has not run setDetail yet); a notify
			// fired at the throw statement sees the fully-built PE. Also measures
			// current-prod behaviour on the listener-injected cfcatch scope.
			it( "cfthrow type= preserves detail/errorCode in cfcatch at uncaught stop", function() {
				if ( !supportsExceptionBreakpoints() ) {
					systemOutput( "skipping: exception breakpoints not supported", true );
					return;
				}

				dap.setExceptionBreakpoints( [ "uncaught" ] );
				triggerArtifact( "exception-target.cfm", { throwException: true, catchException: false, throwMode: "type" }, true );

				var stopped = dap.waitForEvent( "stopped", 2000 );
				expect( stopped.body.reason ).toBe( "exception" );
				var threadId = stopped.body.threadId;

				var frame = getTopFrame( threadId );
				var cfcatchScope = getScopeByName( frame.id, "cfcatch" );
				var vars = dap.getVariables( cfcatchScope.variablesReference ).body.variables;
				var varMap = {};
				for ( var v in vars ) { varMap[ v.name ] = v.value; }

				expect( varMap ).toHaveKey( "detail", "cfcatch should expose detail" );
				expect( varMap.detail ).toInclude( "This is for testing", "cfcatch.detail should preserve the cfthrow detail= attribute" );

				cleanupThread( threadId );
			} );

			// Top-level 404 — request URL resolves to a template that doesn't exist.
			// There is no live user frame to suspend on (the template never ran), so
			// the uncaught-exception breakpoint MUST NOT fire. Lucee still logs the
			// MissingIncludeException to the console and returns a 404; that's the
			// appropriate surface area for this case.
			it( "MissingIncludeException (top-level 404) does NOT fire the uncaught breakpoint", function() {
				if ( !supportsExceptionBreakpoints() ) {
					systemOutput( "skipping: exception breakpoints not supported", true );
					return;
				}

				dap.setExceptionBreakpoints( [ "uncaught" ] );
				triggerArtifact( "this-template-does-not-exist.cfm", {}, true );

				sleep( 2000 );
				expect( dap.hasEvent( "stopped" ) ).toBeFalse( "Top-level 404 has no live frame to break on — uncaught breakpoint must not fire" );

				waitForHttpComplete();
			} );

			// Nested variant: outer .cfm exists and includes a template that
			// doesn't. MissingIncludeException is thrown from PageSourceImpl.loadPage
			// while the outer _doInclude frame is still live, so the stack MUST
			// contain the outer parent frame (whether or not the fix also surfaces
			// a synthetic frame for the missing template).
			it( "MissingIncludeException from nested cfinclude exposes outer frame", function() {
				if ( !supportsExceptionBreakpoints() ) {
					systemOutput( "skipping: exception breakpoints not supported", true );
					return;
				}

				dap.setExceptionBreakpoints( [ "uncaught" ] );
				triggerArtifact( "exception-nested-missing-include-target.cfm", {}, true );

				var stopped = dap.waitForEvent( "stopped", 2000 );
				expect( stopped.body.reason ).toBe( "exception" );
				var threadId = stopped.body.threadId;

				var frames = dap.stackTrace( threadId ).body.stackFrames;
				expect( frames.len() ).toBeGTE( 1, "MissingIncludeException from nested cfinclude should expose at least one frame" );

				var outerSeen = false;
				for ( var frame in frames ) {
					var path = replace( frame.source.path ?: "", "\", "/", "all" );
					if ( right( path, len( "exception-nested-missing-include-target.cfm" ) ) == "exception-nested-missing-include-target.cfm" ) {
						outerSeen = true;
						break;
					}
				}
				expect( outerSeen ).toBeTrue( "Stack should contain the outer parent frame (exception-nested-missing-include-target.cfm)" );

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
