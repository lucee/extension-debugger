@echo off
setlocal EnableDelayedExpansion

rem ============================================================
rem DAP Stepping Test
rem
rem This test requires TWO Lucee instances:
rem   1. Debuggee: Runs with luceedebug agent, serves HTTP on 8888
rem   2. Test runner: Runs this test script, connects to DAP on 10000
rem
rem Since script-runner runs headless, we need an alternative.
rem This script starts CommandBox for the debuggee.
rem ============================================================

set SCRIPT_RUNNER=D:\work\script-runner
set PROFILING_DIR=D:\work\lucee-extensions\luceedebug\profiling
set LUCEE_JAR=D:\work\lucee7\loader\target\lucee-7.0.1.97-SNAPSHOT.jar
set LUCEEDEBUG_JAR=D:\work\lucee-extensions\luceedebug\luceedebug\build\libs\luceedebug-2.0.15.jar
set JDWP_PORT=9999
set DEBUG_PORT=10000

echo.
echo ============================================================
echo DAP Stepping Test
echo ============================================================
echo.
echo This test requires TWO Lucee instances running simultaneously.
echo.
echo Option 1: Manual Setup
echo   1. Start debuggee with HTTP server (CommandBox or Tomcat)
echo      - Lucee with luceedebug agent on DAP port 10000
echo      - HTTP on port 8888
echo      - Webroot: %PROFILING_DIR%
echo   2. Run this script to execute the test
echo.
echo Option 2: Use existing test infrastructure
echo   Run test-native-frames-with-agent.bat to verify agent works
echo   Then manually test stepping with VS Code
echo.
echo ============================================================
echo.

rem For now, just run the basic native frames test
echo Running native frames test first...
call "%PROFILING_DIR%\test-native-frames-with-agent.bat"

endlocal
