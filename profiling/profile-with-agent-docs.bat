@echo off
setlocal

rem ============================================================
rem Profile luceedebug - WITH AGENT using lucee-docs build
rem ============================================================

set SCRIPT_RUNNER=D:\work\script-runner
set DOCS_DIR=D:\work\lucee-docs
set LUCEEDEBUG_JAR=D:\work\lucee-extensions\luceedebug\luceedebug\build\libs\luceedebug-2.0.15.jar
set OUTPUT_DIR=D:\work\lucee-extensions\luceedebug\profiling\output
set JFC_CONFIG=D:\work\lucee-testlab\jfc-high-frequency.jfc
set JDWP_PORT=9999
set DEBUG_PORT=10000

rem Extensions from lucee-docs build
set EXTENSIONS=60772C12-F179-D555-8E2CD2B4F7428718;version=4.0.0.0,D46B46A9-A0E3-44E1-D972A04AC3A8DC10;version=2.0.0.1,EFDEB172-F52E-4D84-9CD1A1F561B3DFC8;version=3.0.0.163-RC,FAD67145-E3AE-30F8-1C11A6CCF544F0B7;version=2.0.0.3,6E2CB28F-98FB-4B51-B6BE6C64ADF35473;version=1.0.0.6,DF28D0A4-6748-44B9-A2FDC12E4E2E4D38;version=1.5.0.5,7891D723-8F78-45F5-B7E333A22F8467CA;version=1.0.0.9,261114AC-7372-4CA8-BA7090895E01682D;version=1.0.0.5,A03F4335-BDEF-44DE-946FB16C47802F96;version=1.0.0.0-RC,3F9DFF32-B555-449D-B0EB5DB723044045;version=3.0.0.17

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
echo AGENT PROFILE - lucee-docs build with luceedebug
echo ============================================================
echo.
echo luceedebug JAR: %LUCEEDEBUG_JAR%
echo.

call ant -buildfile "%SCRIPT_RUNNER%" -DluceeVersionQuery="7/all/jar" -Dwebroot="%DOCS_DIR%" -Dexecute="build.cfm" -Dextensions="%EXTENSIONS%" -Djdwp="true" -DjdwpPort="%JDWP_PORT%" -DjavaAgent="%LUCEEDEBUG_JAR%" -DjavaAgentArgs="jdwpHost=localhost,jdwpPort=%JDWP_PORT%,debugHost=0.0.0.0,debugPort=%DEBUG_PORT%,jarPath=%LUCEEDEBUG_JAR%" -DFlightRecording="true" -DFlightRecordingFilename="%OUTPUT_DIR%\with-agent-docs.jfr" -DFlightRecordingSettings="%JFC_CONFIG%" -DuniqueWorkingDir="true" -DpostCleanup="false" > "%OUTPUT_DIR%\with-agent-docs-output.txt" 2>&1

echo.
echo Results saved to: %OUTPUT_DIR%\with-agent-docs-output.txt
echo JFR saved to: %OUTPUT_DIR%\with-agent-docs.jfr
echo.

type "%OUTPUT_DIR%\with-agent-docs-output.txt" | findstr /C:"Total time:" /C:"BUILD" /C:"luceedebug"

endlocal
