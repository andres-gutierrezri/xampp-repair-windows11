@echo off
rem ==========================================================================
rem  Lanzador seguro de Repair-Xampp.ps1 para cuentas sin administrador.
rem  Aplica -ExecutionPolicy Bypass UNICAMENTE al proceso hijo; no cambia
rem  ninguna directiva persistente del equipo. Reenvia todos los argumentos.
rem  Ejemplo: src\run-powershell-repair.bat -StopMySql
rem ==========================================================================
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Repair-Xampp.ps1" %*
set "RC=%ERRORLEVEL%"
echo.
echo Codigo de salida: %RC%
pause
endlocal & exit /b %RC%
