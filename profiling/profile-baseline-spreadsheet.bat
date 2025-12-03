@echo off
setlocal

rem ============================================================
rem Profile luceedebug - BASELINE using lucee-spreadsheet tests
rem ============================================================

set SCRIPT_RUNNER=D:\work\script-runner
set SPREADSHEET_DIR=D:\work\lucee-spreadsheet
set OUTPUT_DIR=D:\work\lucee-extensions\luceedebug\profiling\output
set JFC_CONFIG=D:\work\lucee-testlab\jfc-high-frequency.jfc

rem Create output directory
if not exist "%OUTPUT_DIR%" mkdir "%OUTPUT_DIR%"

echo.
echo ============================================================
echo BASELINE PROFILE - lucee-spreadsheet without luceedebug
echo ============================================================
echo.

call ant -buildfile "%SCRIPT_RUNNER%" -DluceeVersionQuery="7/all/jar" -Dwebroot="%SPREADSHEET_DIR%" -Dexecute="/test/index.cfm" -DFlightRecording="true" -DFlightRecordingFilename="%OUTPUT_DIR%\baseline-spreadsheet.jfr" -DFlightRecordingSettings="%JFC_CONFIG%" -DpostCleanup="false" > "%OUTPUT_DIR%\baseline-spreadsheet-output.txt" 2>&1

echo.
echo Results saved to: %OUTPUT_DIR%\baseline-spreadsheet-output.txt
echo JFR saved to: %OUTPUT_DIR%\baseline-spreadsheet.jfr
echo.

type "%OUTPUT_DIR%\baseline-spreadsheet-output.txt" | findstr /C:"Total time:" /C:"BUILD"

endlocal
