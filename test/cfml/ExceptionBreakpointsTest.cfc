/**
 * Tests for exception breakpoints (break on uncaught exceptions).
 */
component extends="org.lucee.cfml.test.LuceeTestCase" labels="dap" {

	include "DapTestCase.cfm";

	variables.targetFile = "";

	function beforeAll() {
		setupDap();
		variables.targetFile = getArtifactPath( "exception-target.cfm" );
	}

	function afterEach() {
		// Clear exception breakpoints
		dap.setExceptionBreakpoints( [] );
		clearBreakpoints( variables.targetFile );
	}

	// ========== Set Exception Breakpoints ==========

	function testSetExceptionBreakpoints() {
		var response = dap.setExceptionBreakpoints( [ "uncaught" ] );

		// Response should indicate success
		expect( response.success ).toBeTrue();
	}

	function testClearExceptionBreakpoints() {
		// Set then clear
		dap.setExceptionBreakpoints( [ "uncaught" ] );
		var response = dap.setExceptionBreakpoints( [] );

		expect( response.success ).toBeTrue();
	}

	// ========== Uncaught Exception Breakpoint ==========

	function testUncaughtExceptionBreakpointHits() skip="notSupportsExceptionBreakpoints" {
		dap.setExceptionBreakpoints( [ "uncaught" ] );

		// Trigger uncaught exception
		triggerArtifact( "exception-target.cfm", { throwException: true, catchException: false }, true );

		var stopped = dap.waitForEvent( "stopped", 2000 );

		expect( stopped.body.reason ).toBe( "exception" );

		cleanupThread( stopped.body.threadId );
	}

	function testCaughtExceptionDoesNotTriggerUncaughtBreakpoint() skip="notSupportsExceptionBreakpoints" {
		dap.setExceptionBreakpoints( [ "uncaught" ] );

		// Trigger caught exception
		triggerArtifact( "exception-target.cfm", { throwException: true, catchException: true } );

		// Should NOT stop
		sleep( 2000 );
		var hasStoppedEvent = dap.hasEvent( "stopped" );
		expect( hasStoppedEvent ).toBeFalse( "Caught exception should not trigger uncaught breakpoint" );

		waitForHttpComplete();
	}

	function testNoExceptionDoesNotTriggerBreakpoint() skip="notSupportsExceptionBreakpoints" {
		dap.setExceptionBreakpoints( [ "uncaught" ] );

		// Trigger without exception
		triggerArtifact( "exception-target.cfm", { throwException: false, catchException: false } );

		// Should NOT stop
		sleep( 2000 );
		var hasStoppedEvent = dap.hasEvent( "stopped" );
		expect( hasStoppedEvent ).toBeFalse( "No exception should not trigger breakpoint" );

		waitForHttpComplete();
	}

	// ========== Exception Info ==========

	function testExceptionInfoReturnsDetails() skip="notSupportsExceptionBreakpoints" {
		dap.setExceptionBreakpoints( [ "uncaught" ] );

		// Trigger uncaught exception
		triggerArtifact( "exception-target.cfm", { throwException: true, catchException: false }, true );

		var stopped = dap.waitForEvent( "stopped", 2000 );
		var threadId = stopped.body.threadId;

		// Get exception info
		var exceptionInfo = dap.exceptionInfo( threadId );

		expect( exceptionInfo.body ).toHaveKey( "exceptionId" );
		expect( exceptionInfo.body ).toHaveKey( "description" );

		// Should contain our test exception message
		expect( exceptionInfo.body.description ).toInclude( "Intentional test exception" );

		cleanupThread( threadId );
	}

	function testExceptionInfoIncludesType() skip="notSupportsExceptionBreakpoints" {
		dap.setExceptionBreakpoints( [ "uncaught" ] );

		// Trigger uncaught exception
		triggerArtifact( "exception-target.cfm", { throwException: true, catchException: false }, true );

		var stopped = dap.waitForEvent( "stopped", 2000 );
		var threadId = stopped.body.threadId;

		// Get exception info
		var exceptionInfo = dap.exceptionInfo( threadId );

		// Exception ID should be the type
		expect( exceptionInfo.body.exceptionId ).toInclude( "TestException" );

		cleanupThread( threadId );
	}

	// ========== Stack Trace at Exception ==========

	function testStackTraceAtException() skip="notSupportsExceptionBreakpoints" {
		dap.setExceptionBreakpoints( [ "uncaught" ] );

		// Trigger uncaught exception
		triggerArtifact( "exception-target.cfm", { throwException: true, catchException: false }, true );

		var stopped = dap.waitForEvent( "stopped", 2000 );
		var threadId = stopped.body.threadId;

		// Get stack trace
		var stackResponse = dap.stackTrace( threadId );
		var frames = stackResponse.body.stackFrames;

		expect( frames.len() ).toBeGTE( 2, "Should have at least 2 stack frames" );

		// Top frame should be in riskyFunction where exception was thrown
		expect( frames[ 1 ].name ).toInclude( "riskyFunction" );

		cleanupThread( threadId );
	}

	// ========== Variables at Exception ==========

	function testVariablesAtException() skip="notSupportsExceptionBreakpoints" {
		dap.setExceptionBreakpoints( [ "uncaught" ] );

		// Trigger uncaught exception
		triggerArtifact( "exception-target.cfm", { throwException: true, catchException: false }, true );

		var stopped = dap.waitForEvent( "stopped", 2000 );
		var threadId = stopped.body.threadId;

		// Should be able to inspect variables even at exception
		var frame = getTopFrame( threadId );
		var argsScope = getScopeByName( frame.id, "Arguments" );

		var shouldThrow = getVariableByName( argsScope.variablesReference, "shouldThrow" );
		expect( shouldThrow.value.lcase() ).toBe( "true" );

		cleanupThread( threadId );
	}

	// ========== Continue After Exception ==========

	function testContinueAfterException() skip="notSupportsExceptionBreakpoints" {
		dap.setExceptionBreakpoints( [ "uncaught" ] );

		// Trigger uncaught exception
		triggerArtifact( "exception-target.cfm", { throwException: true, catchException: false }, true );

		var stopped = dap.waitForEvent( "stopped", 2000 );
		var threadId = stopped.body.threadId;

		// Continue should let the exception propagate
		dap.continueThread( threadId );

		// HTTP request should complete (with error)
		var result = waitForHttpComplete();

		// The request should have failed with an error status or error response
		// (Depends on how Lucee handles uncaught exceptions)
		expect( result ).toHaveKey( "status" );
	}

	// ========== Exception Logging ==========

	function testExceptionLoggingWithLogExceptionsEnabled() skip="notSupportsExceptionBreakpoints" {
		// Reconnect with exception logging enabled
		teardownDap();
		setupDap( logLevel = "info", logExceptions = true );

		dap.setExceptionBreakpoints( [ "uncaught" ] );

		// Trigger uncaught exception
		triggerArtifact( "exception-target.cfm", { throwException: true, catchException = false }, true );

		var stopped = dap.waitForEvent( "stopped", 2000 );

		// Drain output events
		var events = dap.drainEvents();
		var foundExceptionLog = false;

		systemOutput( "Checking #events.len()# events for exception logging", true );

		for ( var event in events ) {
			if ( event.event == "output" ) {
				systemOutput( "Output event: category=#event.body.category# output=#event.body.output#", true );
				// Should see exception details in output
				if ( event.body.output contains "TestException" && event.body.output contains "Intentional test exception" ) {
					foundExceptionLog = true;
					expect( event.body.category ).toBe( "stderr", "Exception logging should use stderr category" );
				}
			}
		}

		expect( foundExceptionLog ).toBeTrue( "Exception should be logged to debug console when logExceptions=true" );

		cleanupThread( stopped.body.threadId );

		// Restore original setup for subsequent tests
		teardownDap();
		setupDap();
		variables.targetFile = getArtifactPath( "exception-target.cfm" );
	}

	function testExceptionLoggingDisabled() skip="notSupportsExceptionBreakpoints" {
		// Reconnect with exception logging explicitly disabled
		teardownDap();
		setupDap( logExceptions = false );

		dap.setExceptionBreakpoints( [ "uncaught" ] );

		// Trigger uncaught exception
		triggerArtifact( "exception-target.cfm", { throwException: true, catchException: false }, true );

		var stopped = dap.waitForEvent( "stopped", 2000 );

		// Drain output events
		var events = dap.drainEvents();
		var foundExceptionLog = false;

		for ( var event in events ) {
			if ( event.event == "output" && event.body.output contains "TestException" ) {
				foundExceptionLog = true;
			}
		}

		// Exception details should NOT be logged when logExceptions is false
		expect( foundExceptionLog ).toBeFalse( "Exception should NOT be logged to debug console when logExceptions=false" );

		cleanupThread( stopped.body.threadId );
	}

	function testOnExceptionCalledLogsAtDebugLevel() skip="notSupportsExceptionBreakpoints" {
		// Reconnect with debug log level to see onException calls
		teardownDap();
		setupDap( logLevel = "debug" );

		dap.setExceptionBreakpoints( [ "uncaught" ] );

		// Trigger uncaught exception
		triggerArtifact( "exception-target.cfm", { throwException: true, catchException: false }, true );

		var stopped = dap.waitForEvent( "stopped", 2000 );

		// Drain output events
		var events = dap.drainEvents();
		var foundOnExceptionLog = false;

		systemOutput( "Checking events for onException logging at debug level", true );

		for ( var event in events ) {
			if ( event.event == "output" ) {
				systemOutput( "Output event: #event.body.output#", true );
				// Should see onException being called at DEBUG level
				if ( event.body.output contains "onException" ) {
					foundOnExceptionLog = true;
				}
			}
		}

		expect( foundOnExceptionLog ).toBeTrue( "onException calls should be logged at DEBUG level" );

		cleanupThread( stopped.body.threadId );

		// Restore original setup
		teardownDap();
		setupDap();
		variables.targetFile = getArtifactPath( "exception-target.cfm" );
	}

}
