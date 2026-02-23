@echo off
powershell -ExecutionPolicy Bypass -Command "& '%~dp0build_release_oneclick.ps1'; exit $LASTEXITCODE"
if errorlevel 1 (
  echo.
  echo [ERROR] Build failed.
  pause
  exit /b 1
)
echo.
echo [OK] Build completed.
pause