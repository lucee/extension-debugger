@echo off
setlocal

rem ============================================================
rem Test DAP threads() command against running luceedebug server
rem ============================================================

set SCRIPT_RUNNER=D:\work\script-runner
set PROFILING_DIR=D:\work\lucee-extensions\luceedebug\profiling
set LUCEE_JAR=D:\work\lucee7\loader\target\lucee-7.1.0.7-ALPHA.jar

rem Check if Lucee JAR exists
if not exist "%LUCEE_JAR%" (
    echo ERROR: Lucee JAR not found at %LUCEE_JAR%
    echo Run: cd /d/work/lucee7/loader ^&^& ant fast
    exit /b 1
)

echo.
echo ============================================================
echo Testing DAP Threads Command
echo ============================================================
echo.
echo This test connects to an already-running luceedebug DAP server
echo Make sure your test Tomcat with the extension is running on port 10000
echo.

call ant -buildfile "%SCRIPT_RUNNER%" -DluceeJar="%LUCEE_JAR%" -Dwebroot="%PROFILING_DIR%" -Dexecute="test-threads.cfm" -DpostCleanup="false" -DpreCleanup="true"

endlocal
