/**
 * Tests for exception breakpoints (break on uncaught exceptions).
 *
 * BDD style — skip=notSupportsExceptionBreakpoints() on capability-gated specs.
 */
component extends="org.lucee.cfml.test.LuceeTestCase" labels="dap" {

	include "DapTestCase.cfm";

	variables.targetFile = "";

	function beforeAll() {
		setupDap();
		variables.targetFile = getArtifactPath( "exception-target.cfm" );
	}

	function run( testResults, testBox ) {
		describe( "DAP exception breakpoints", function() {

			beforeEach( function() {
				dap.drainEvents();
			} );

			afterEach( function() {
				// Clear exception + line breakpoints.
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

			it( "setExceptionBreakpoints with 'uncaught' succeeds", function() {
				var response = dap.setExceptionBreakpoints( [ "uncaught" ] );
				expect( response.success ).toBeTrue();
			} );

			it( "clearing exception breakpoints succeeds", function() {
				dap.setExceptionBreakpoints( [ "uncaught" ] );
				var response = dap.setExceptionBreakpoints( [] );
				expect( response.success ).toBeTrue();
			} );

			it( title="an uncaught exception triggers a stopped event with reason=exception", body=function() {
				dap.setExceptionBreakpoints( [ "uncaught" ] );

				triggerArtifact( "exception-target.cfm", { throwException: true, catchException: false }, true );

				var stopped = dap.waitForEvent( "stopped", 2000 );

				expect( stopped.body.reason ).toBe( "exception" );

				cleanupThread( stopped.body.threadId );
			}, skip=notSupportsExceptionBreakpoints() );

			it( title="inner exception inside a cftry block stops at the throw", body=function() {
				dap.setExceptionBreakpoints( [ "uncaught" ] );

				triggerArtifact( "exception-target.cfm", { throwException: true, catchException: true }, true );

				var stopped = dap.waitForEvent( "stopped", 2000 );
				expect( stopped.body.reason ).toBe( "exception" );

				cleanupThread( stopped.body.threadId );
			}, skip=notSupportsExceptionBreakpoints() );

			it( title="a run with no exception does NOT trigger the breakpoint", body=function() {
				dap.setExceptionBreakpoints( [ "uncaught" ] );

				triggerArtifact( "exception-target.cfm", { throwException: false, catchException: false } );

				sleep( 2000 );
				var hasStoppedEvent = dap.hasEvent( "stopped" );
				expect( hasStoppedEvent ).toBeFalse( "No exception should not trigger breakpoint" );

				waitForHttpComplete();
			}, skip=notSupportsExceptionBreakpoints() );

			it( title="exceptionInfo returns description and exceptionId", body=function() {
				dap.setExceptionBreakpoints( [ "uncaught" ] );

				triggerArtifact( "exception-target.cfm", { throwException: true, catchException: false }, true );

				var stopped = dap.waitForEvent( "stopped", 2000 );
				var threadId = stopped.body.threadId;

				var exceptionInfo = dap.exceptionInfo( threadId );

				expect( exceptionInfo.body ).toHaveKey( "exceptionId" );
				expect( exceptionInfo.body ).toHaveKey( "description" );
				expect( exceptionInfo.body.description ).toInclude( "Intentional test exception" );

				cleanupThread( threadId );
			}, skip=notSupportsExceptionBreakpoints() );

			it( title="exceptionInfo.exceptionId includes the exception type name (TestException)", body=function() {
				dap.setExceptionBreakpoints( [ "uncaught" ] );

				triggerArtifact( "exception-target.cfm", { throwException: true, catchException: false }, true );

				var stopped = dap.waitForEvent( "stopped", 2000 );
				var threadId = stopped.body.threadId;

				var exceptionInfo = dap.exceptionInfo( threadId );

				expect( exceptionInfo.body.exceptionId ).toInclude( "TestException" );

				cleanupThread( threadId );
			}, skip=notSupportsExceptionBreakpoints() );

			it( title="stack trace at exception shows the throwing function on top", body=function() {
				dap.setExceptionBreakpoints( [ "uncaught" ] );

				triggerArtifact( "exception-target.cfm", { throwException: true, catchException: false }, true );

				var stopped = dap.waitForEvent( "stopped", 2000 );
				var threadId = stopped.body.threadId;

				var stackResponse = dap.stackTrace( threadId );
				var frames = stackResponse.body.stackFrames;

				expect( frames.len() ).toBeGTE( 2, "Should have at least 2 stack frames" );
				expect( frames[ 1 ].name ).toInclude( "riskyFunction" );

				cleanupThread( threadId );
			}, skip=notSupportsExceptionBreakpoints() );

			it( title="variables are inspectable when stopped at an exception", body=function() {
				dap.setExceptionBreakpoints( [ "uncaught" ] );

				triggerArtifact( "exception-target.cfm", { throwException: true, catchException: false }, true );

				var stopped = dap.waitForEvent( "stopped", 2000 );
				var threadId = stopped.body.threadId;

				var frame = getTopFrame( threadId );
				var argsScope = getScopeByName( frame.id, "Arguments" );

				var shouldThrow = getVariableByName( argsScope.variablesReference, "shouldThrow" );
				expect( shouldThrow.value.lcase() ).toBe( "true" );

				cleanupThread( threadId );
			}, skip=notSupportsExceptionBreakpoints() );

			it( title="continuing after an exception lets it propagate and the HTTP request completes", body=function() {
				dap.setExceptionBreakpoints( [ "uncaught" ] );

				triggerArtifact( "exception-target.cfm", { throwException: true, catchException: false }, true );

				var stopped = dap.waitForEvent( "stopped", 2000 );
				var threadId = stopped.body.threadId;

				dap.continueThread( threadId );

				var result = waitForHttpComplete();
				expect( result ).toHaveKey( "status" );
			}, skip=notSupportsExceptionBreakpoints() );

			it( title="logExceptions=true: exception details appear as stderr output events", body=function() {
				teardownDap();
				setupDap( logLevel = "info", logExceptions = true );

				dap.setExceptionBreakpoints( [ "uncaught" ] );

				triggerArtifact( "exception-target.cfm", { throwException: true, catchException: false }, true );

				var stopped = dap.waitForEvent( "stopped", 2000 );

				var events = dap.drainEvents();
				var foundExceptionLog = false;

				systemOutput( "Checking #events.len()# events for exception logging", true );

				for ( var event in events ) {
					if ( event.event == "output" ) {
						systemOutput( "Output event: category=#event.body.category# output=#event.body.output#", true );
						if ( event.body.output contains "TestException" && event.body.output contains "Intentional test exception" ) {
							foundExceptionLog = true;
							expect( event.body.category ).toBe( "stderr", "Exception logging should use stderr category" );
						}
					}
				}

				expect( foundExceptionLog ).toBeTrue( "Exception should be logged to debug console when logExceptions=true" );

				cleanupThread( stopped.body.threadId );

				teardownDap();
				setupDap();
				variables.targetFile = getArtifactPath( "exception-target.cfm" );
			}, skip=notSupportsExceptionBreakpoints() );

			it( title="logExceptions=false: exception details are NOT output events", body=function() {
				teardownDap();
				setupDap( logExceptions = false );

				dap.setExceptionBreakpoints( [ "uncaught" ] );

				triggerArtifact( "exception-target.cfm", { throwException: true, catchException: false }, true );

				var stopped = dap.waitForEvent( "stopped", 2000 );

				var events = dap.drainEvents();
				var foundExceptionLog = false;

				for ( var event in events ) {
					if ( event.event == "output" && event.body.output contains "TestException" ) {
						foundExceptionLog = true;
					}
				}

				expect( foundExceptionLog ).toBeFalse( "Exception should NOT be logged to debug console when logExceptions=false" );

				cleanupThread( stopped.body.threadId );
			}, skip=notSupportsExceptionBreakpoints() );

			it( title="logLevel=debug: onException calls appear as DEBUG-level output events", body=function() {
				teardownDap();
				setupDap( logLevel = "debug" );

				dap.setExceptionBreakpoints( [ "uncaught" ] );

				triggerArtifact( "exception-target.cfm", { throwException: true, catchException: false }, true );

				var stopped = dap.waitForEvent( "stopped", 2000 );

				var events = dap.drainEvents();
				var foundOnExceptionLog = false;

				systemOutput( "Checking events for onException logging at debug level", true );

				for ( var event in events ) {
					if ( event.event == "output" ) {
						systemOutput( "Output event: #event.body.output#", true );
						if ( event.body.output contains "onException" ) {
							foundOnExceptionLog = true;
						}
					}
				}

				expect( foundOnExceptionLog ).toBeTrue( "onException calls should be logged at DEBUG level" );

				cleanupThread( stopped.body.threadId );

				teardownDap();
				setupDap();
				variables.targetFile = getArtifactPath( "exception-target.cfm" );
			}, skip=notSupportsExceptionBreakpoints() );

		} );
	}
}
