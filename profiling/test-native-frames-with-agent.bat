@echo off
setlocal

rem ============================================================
rem Test native debugger frames with luceedebug agent
rem ============================================================

set SCRIPT_RUNNER=D:\work\script-runner
set PROFILING_DIR=D:\work\lucee-extensions\luceedebug\profiling
set LUCEE_JAR=D:\work\lucee7\loader\target\lucee-7.1.0.7-ALPHA.jar
set LUCEEDEBUG_JAR=D:\work\lucee-extensions\luceedebug\luceedebug\build\libs\luceedebug-2.0.15.jar
set JDWP_PORT=9999
set DEBUG_PORT=10000

rem Check if Lucee JAR exists
if not exist "%LUCEE_JAR%" (
    echo ERROR: Lucee JAR not found at %LUCEE_JAR%
    echo Run: cd /d/work/lucee7/loader ^&^& ant fast
    exit /b 1
)

rem Check if luceedebug JAR exists
if not exist "%LUCEEDEBUG_JAR%" (
    echo ERROR: luceedebug JAR not found at %LUCEEDEBUG_JAR%
    echo Run: cd luceedebug ^&^& gradlew shadowJar
    exit /b 1
)

echo.
echo ============================================================
echo Testing Native Debugger Frames with luceedebug agent
echo ============================================================
echo.
echo Lucee JAR: %LUCEE_JAR%
echo luceedebug JAR: %LUCEEDEBUG_JAR%
echo.
echo DAP server will listen on port %DEBUG_PORT%
echo Connect VS Code debugger to test breakpoints
echo.

rem Enable debugger via env var
set LUCEE_DEBUGGER_ENABLED=true

rem Enable trace logging to console
set lucee_logging_force_level=trace
set lucee_logging_force_appender=console

call ant -buildfile "%SCRIPT_RUNNER%" -DluceeJar="%LUCEE_JAR%" -Dwebroot="%PROFILING_DIR%" -Dexecute="test-debugger-frames.cfm" -Djdwp="true" -DjdwpPort="%JDWP_PORT%" -DjavaAgent="%LUCEEDEBUG_JAR%" -DjavaAgentArgs="jdwpHost=localhost,jdwpPort=%JDWP_PORT%,debugHost=0.0.0.0,debugPort=%DEBUG_PORT%,jarPath=%LUCEEDEBUG_JAR%" -DpostCleanup="false" -DpreCleanup="true"

endlocal
