@echo off
setlocal

rem ============================================================
rem Compare baseline vs with-agent profiling results
rem ============================================================

set OUTPUT_DIR=%~dp0output

echo.
echo ============================================================
echo PERFORMANCE COMPARISON
echo ============================================================
echo.

echo --- BASELINE (no luceedebug) ---
if exist "%OUTPUT_DIR%\baseline-output.txt" (
    type "%OUTPUT_DIR%\baseline-output.txt" | findstr /C:"Time:"
) else (
    echo No baseline results found. Run profile-baseline.bat first.
)

echo.
echo --- WITH AGENT (luceedebug loaded) ---
if exist "%OUTPUT_DIR%\with-agent-output.txt" (
    type "%OUTPUT_DIR%\with-agent-output.txt" | findstr /C:"Time:"
) else (
    echo No agent results found. Run profile-with-agent.bat first.
)

echo.
echo ============================================================
echo JFR FILES
echo ============================================================
echo.

if exist "%OUTPUT_DIR%\baseline.jfr" (
    echo Baseline: %OUTPUT_DIR%\baseline.jfr
) else (
    echo Baseline: NOT FOUND
)

if exist "%OUTPUT_DIR%\with-agent.jfr" (
    echo With Agent: %OUTPUT_DIR%\with-agent.jfr
) else (
    echo With Agent: NOT FOUND
)

echo.
echo To analyse in JDK Mission Control:
echo   jmc -open "%OUTPUT_DIR%\baseline.jfr"
echo   jmc -open "%OUTPUT_DIR%\with-agent.jfr"
echo.

endlocal
