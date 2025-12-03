@echo off
setlocal

rem ============================================================
rem Profile luceedebug - WITH AGENT (no debugger connected)
rem ============================================================

set SCRIPT_RUNNER=D:\work\script-runner
set PROFILING_DIR=D:\work\lucee-extensions\luceedebug\profiling
set LUCEEDEBUG_JAR=D:\work\lucee-extensions\luceedebug\luceedebug\build\libs\luceedebug-2.0.15.jar
set OUTPUT_DIR=%PROFILING_DIR%\output
set JFC_CONFIG=D:\work\lucee-testlab\jfc-high-frequency.jfc
set JDWP_PORT=9999
set DEBUG_PORT=10000

rem Check if luceedebug JAR exists
if not exist "%LUCEEDEBUG_JAR%" (
    echo ERROR: luceedebug JAR not found at %LUCEEDEBUG_JAR%
    echo Run: cd luceedebug ^&^& gradlew shadowJar
    exit /b 1
)

rem Create output directory
if not exist "%OUTPUT_DIR%" mkdir "%OUTPUT_DIR%"

echo.
echo ============================================================
echo AGENT PROFILE - Lucee with luceedebug (no debugger connected)
echo ============================================================
echo.
echo luceedebug JAR: %LUCEEDEBUG_JAR%
echo.

call ant -buildfile "%SCRIPT_RUNNER%" -DluceeVersionQuery="7/all/jar" -Dwebroot="%PROFILING_DIR%" -Dexecute="benchmark.cfm" -Djdwp="true" -DjdwpPort="%JDWP_PORT%" -DjavaAgent="%LUCEEDEBUG_JAR%" -DjavaAgentArgs="jdwpHost=localhost,jdwpPort=%JDWP_PORT%,debugHost=0.0.0.0,debugPort=%DEBUG_PORT%,jarPath=%LUCEEDEBUG_JAR%" -DFlightRecording="true" -DFlightRecordingFilename="%OUTPUT_DIR%\with-agent.jfr" -DFlightRecordingSettings="%JFC_CONFIG%" -DpostCleanup="false" > "%OUTPUT_DIR%\with-agent-output.txt" 2>&1

echo.
echo Results saved to: %OUTPUT_DIR%\with-agent-output.txt
echo JFR saved to: %OUTPUT_DIR%\with-agent.jfr
echo.

type "%OUTPUT_DIR%\with-agent-output.txt" | findstr /C:"Time:" /C:"===" /C:"Benchmark" /C:"luceedebug"

endlocal
