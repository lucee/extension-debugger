@echo off
setlocal

rem ============================================================
rem Profile luceedebug - BASELINE (no agent)
rem ============================================================

set SCRIPT_RUNNER=D:\work\script-runner
set PROFILING_DIR=D:\work\lucee-extensions\luceedebug\profiling
set OUTPUT_DIR=%PROFILING_DIR%\output
set JFC_CONFIG=D:\work\lucee-testlab\jfc-high-frequency.jfc

rem Create output directory
if not exist "%OUTPUT_DIR%" mkdir "%OUTPUT_DIR%"

echo.
echo ============================================================
echo BASELINE PROFILE - Lucee without luceedebug
echo ============================================================
echo.

call ant -buildfile "%SCRIPT_RUNNER%" -DluceeVersionQuery="7/all/jar" -Dwebroot="%PROFILING_DIR%" -Dexecute="benchmark.cfm" -DFlightRecording="true" -DFlightRecordingFilename="%OUTPUT_DIR%\baseline.jfr" -DFlightRecordingSettings="%JFC_CONFIG%" -DpostCleanup="false" > "%OUTPUT_DIR%\baseline-output.txt" 2>&1

echo.
echo Results saved to: %OUTPUT_DIR%\baseline-output.txt
echo JFR saved to: %OUTPUT_DIR%\baseline.jfr
echo.

type "%OUTPUT_DIR%\baseline-output.txt" | findstr /C:"Time:" /C:"===" /C:"Benchmark"

endlocal
