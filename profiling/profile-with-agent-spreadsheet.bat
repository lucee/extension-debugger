@echo off
setlocal

rem ============================================================
rem Profile luceedebug - WITH AGENT using lucee-spreadsheet tests
rem ============================================================

set SCRIPT_RUNNER=D:\work\script-runner
set SPREADSHEET_DIR=D:\work\lucee-spreadsheet
set LUCEEDEBUG_JAR=D:\work\lucee-extensions\luceedebug\luceedebug\build\libs\luceedebug-2.0.15.jar
set OUTPUT_DIR=D:\work\lucee-extensions\luceedebug\profiling\output
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
echo AGENT PROFILE - lucee-spreadsheet with luceedebug
echo ============================================================
echo.
echo luceedebug JAR: %LUCEEDEBUG_JAR%
echo.

call ant -buildfile "%SCRIPT_RUNNER%" -DluceeVersionQuery="7/all/jar" -Dwebroot="%SPREADSHEET_DIR%" -Dexecute="/test/index.cfm" -Djdwp="true" -DjdwpPort="%JDWP_PORT%" -DjavaAgent="%LUCEEDEBUG_JAR%" -DjavaAgentArgs="jdwpHost=localhost,jdwpPort=%JDWP_PORT%,debugHost=0.0.0.0,debugPort=%DEBUG_PORT%,jarPath=%LUCEEDEBUG_JAR%" -DFlightRecording="true" -DFlightRecordingFilename="%OUTPUT_DIR%\with-agent-spreadsheet.jfr" -DFlightRecordingSettings="%JFC_CONFIG%" -DpostCleanup="false" > "%OUTPUT_DIR%\with-agent-spreadsheet-output.txt" 2>&1

echo.
echo Results saved to: %OUTPUT_DIR%\with-agent-spreadsheet-output.txt
echo JFR saved to: %OUTPUT_DIR%\with-agent-spreadsheet.jfr
echo.

type "%OUTPUT_DIR%\with-agent-spreadsheet-output.txt" | findstr /C:"Total time:" /C:"BUILD" /C:"luceedebug"

endlocal
