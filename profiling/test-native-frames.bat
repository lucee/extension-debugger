@echo off
setlocal

rem ============================================================
rem Test native debugger frames with local Lucee7 build
rem ============================================================

set SCRIPT_RUNNER=D:\work\script-runner
set PROFILING_DIR=D:\work\lucee-extensions\luceedebug\profiling
set LUCEE_JAR=D:\work\lucee7\loader\target\lucee-7.0.1.97-SNAPSHOT.jar

rem Check if Lucee JAR exists
if not exist "%LUCEE_JAR%" (
    echo ERROR: Lucee JAR not found at %LUCEE_JAR%
    echo Run: cd /d/work/lucee7/loader ^&^& ant fast
    exit /b 1
)

echo.
echo ============================================================
echo Testing Native Debugger Frames with local Lucee7 build
echo ============================================================
echo.
echo Lucee JAR: %LUCEE_JAR%
echo.

rem Enable debugger via env var
set LUCEE_DEBUGGER_ENABLED=true

call ant -buildfile "%SCRIPT_RUNNER%" -DluceeJar="%LUCEE_JAR%" -Dwebroot="%PROFILING_DIR%" -Dexecute="test-debugger-frames.cfm" -DpostCleanup="false" -DpreCleanup="true"

endlocal
