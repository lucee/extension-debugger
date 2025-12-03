@echo off
setlocal

rem ============================================================
rem Test luceedebug extension deployment with local Lucee7 build
rem ============================================================

set SCRIPT_RUNNER=D:\work\script-runner
set PROFILING_DIR=D:\work\lucee-extensions\luceedebug\profiling
set LUCEE_JAR=D:\work\lucee7\loader\target\lucee-7.1.0.7-ALPHA.jar
set EXTENSION_DIR=D:\work\lucee-extensions\luceedebug\luceedebug\build\extension

rem Check if Lucee JAR exists
if not exist "%LUCEE_JAR%" (
    echo ERROR: Lucee JAR not found at %LUCEE_JAR%
    echo Run: cd /d/work/lucee7/loader ^&^& ant fast
    exit /b 1
)

rem Check if extension exists
if not exist "%EXTENSION_DIR%\luceedebug-extension-3.0.0.lex" (
    echo ERROR: Extension not found at %EXTENSION_DIR%
    echo Run: cd /d/work/lucee-extensions/luceedebug ^&^& gradlew buildExtension
    exit /b 1
)

echo.
echo ============================================================
echo Testing Luceedebug Extension Deployment
echo ============================================================
echo.
echo Lucee JAR: %LUCEE_JAR%
echo Extension: %EXTENSION_DIR%
echo.

rem Enable debugger via env var - set port to enable
set LUCEE_DEBUGGER_PORT=10000

rem Enable verbose logging
set LUCEE_LOGGING_FORCE_APPENDER=console
set LUCEE_LOGGING_FORCE_LEVEL=debug

call ant -buildfile "%SCRIPT_RUNNER%" -DluceeJar="%LUCEE_JAR%" -DextensionDir="%EXTENSION_DIR%" -Dwebroot="%PROFILING_DIR%" -Dexecute="test-extension.cfm" -DpostCleanup="false" -DpreCleanup="true"

endlocal
