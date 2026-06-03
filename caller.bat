@echo off
:: Verifica se já está rodando como admin
net session >nul 2>&1
if %errorLevel% == 0 (
    goto :admin
) else (
    goto :elevate
)

:elevate
echo.
echo ========================================
echo  Solicitando privilegios de administrador...
echo ========================================
echo.
powershell -Command "Start-Process '%~f0' -Verb RunAs"
exit /b

:admin
echo.
echo ========================================
echo  INSTALADOR AVELL ONE CONTROL - CLEVO
echo ========================================
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1"
pause

