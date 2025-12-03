@echo off
setlocal

set SCRIPT_RUNNER=D:\work\script-runner
set PROFILING_DIR=D:\work\lucee-extensions\luceedebug\profiling
set LUCEE_JAR=D:\work\lucee7\loader\target\lucee-7.0.1.97-SNAPSHOT.jar

if not exist "%LUCEE_JAR%" (
    echo ERROR: Lucee JAR not found at %LUCEE_JAR%
    exit /b 1
)

echo.
echo === Test 1: DEBUGGER_ENABLED=false (should complete immediately) ===
echo.
set LUCEE_DEBUGGER_ENABLED=false
call ant -buildfile "%SCRIPT_RUNNER%" -DluceeJar="%LUCEE_JAR%" -Dwebroot="%PROFILING_DIR%" -Dexecute="test-breakpoint-bif.cfm" -DpostCleanup="false" -DpreCleanup="true" 2>&1 | findstr /C:"===" /C:"isDebuggerEnabled" /C:"breakpoint" /C:"Result"

echo.
echo === Test 2: DEBUGGER_ENABLED=true (will suspend at breakpoint - Ctrl+C to cancel) ===
echo.
set LUCEE_DEBUGGER_ENABLED=true
call ant -buildfile "%SCRIPT_RUNNER%" -DluceeJar="%LUCEE_JAR%" -Dwebroot="%PROFILING_DIR%" -Dexecute="test-breakpoint-bif.cfm" -DpostCleanup="false" -DpreCleanup="true" 2>&1 | findstr /C:"===" /C:"isDebuggerEnabled" /C:"breakpoint" /C:"Result"

endlocal
