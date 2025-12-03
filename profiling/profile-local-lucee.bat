@echo off
setlocal

rem ============================================================
rem Profile local Lucee7 build - test native debug overhead
rem ============================================================

set SCRIPT_RUNNER=D:\work\script-runner
set PROFILING_DIR=D:\work\lucee-extensions\luceedebug\profiling
set LUCEE_JAR=D:\work\lucee7\loader\target\lucee-7.0.1.97-SNAPSHOT.jar
set OUTPUT_DIR=%PROFILING_DIR%\output

rem Check if Lucee JAR exists
if not exist "%LUCEE_JAR%" (
    echo ERROR: Lucee JAR not found at %LUCEE_JAR%
    echo Run: cd /d/work/lucee7/loader ^&^& ant fast
    exit /b 1
)

rem Create output directory
if not exist "%OUTPUT_DIR%" mkdir "%OUTPUT_DIR%"

echo.
echo ============================================================
echo Profile Local Lucee7 Build - Native Debug Overhead Test
echo ============================================================
echo.
echo Lucee JAR: %LUCEE_JAR%
echo.

echo --- Run 1: DEBUGGER_ENABLED=false ---
set LUCEE_DEBUGGER_ENABLED=false
call ant -buildfile "%SCRIPT_RUNNER%" -DluceeJar="%LUCEE_JAR%" -Dwebroot="%PROFILING_DIR%" -Dexecute="benchmark.cfm" -DpostCleanup="false" -DpreCleanup="true" > "%OUTPUT_DIR%\local-debug-off.txt" 2>&1

echo.
echo --- Run 2: DEBUGGER_ENABLED=true ---
set LUCEE_DEBUGGER_ENABLED=true
call ant -buildfile "%SCRIPT_RUNNER%" -DluceeJar="%LUCEE_JAR%" -Dwebroot="%PROFILING_DIR%" -Dexecute="benchmark.cfm" -DpostCleanup="false" -DpreCleanup="true" > "%OUTPUT_DIR%\local-debug-on.txt" 2>&1

echo.
echo ============================================================
echo Results
echo ============================================================
echo.
echo DEBUGGER_ENABLED=false:
type "%OUTPUT_DIR%\local-debug-off.txt" | findstr /C:"Time:"
echo.
echo DEBUGGER_ENABLED=true:
type "%OUTPUT_DIR%\local-debug-on.txt" | findstr /C:"Time:"
echo.

endlocal
