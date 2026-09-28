@echo off
rem ==========================================================================
rem  repair-xampp.bat
rem  Repara XAMPP (Apache y MySQL/MariaDB) en Windows 11 desde una cuenta
rem  local SIN privilegios de administrador.
rem
rem  Uso:    src\repair-xampp.bat [/NOBACKUP] [/ALLOWDUP] [/SKIPAPACHE] [/STOPMYSQL]
rem  Autor:  Ingeniero Andres Felipe Gutierrez Rivera
rem  Version: 1.0.0  -  Licencia MIT
rem
rem  Nota: CMD carece de equivalentes nativos para (a) listar procesos por ruta
rem  ejecutable y (b) fijar la politica de ejecucion de PowerShell; por eso esas
rem  dos operaciones invocan powershell.exe con -ExecutionPolicy Bypass
rem  aplicado SOLO al proceso hijo (no modifica ninguna directiva del equipo).
rem ==========================================================================
setlocal EnableExtensions
chcp 65001 >nul
title Reparacion de XAMPP - Windows 11 (sin administrador)

set "XAMPP=C:\xampp"
set "MYSQL_PORT=3307"
set "FALLOS=0"
set "AVISOS=0"
set "DUPS=0"
set "NOBACKUP="
set "ALLOWDUP="
set "SKIPAPACHE="
set "STOPMYSQL="

rem --- Rutas del proyecto (este archivo esta en <proyecto>\src) --------------
for %%I in ("%~dp0..") do set "PROJECT_DIR=%%~fI"
set "RES=%PROJECT_DIR%\static"

rem --- Argumentos -------------------------------------------------------------
:parse
if "%~1"=="" goto parsed
if /i "%~1"=="/NOBACKUP"   set "NOBACKUP=1"
if /i "%~1"=="/ALLOWDUP"   set "ALLOWDUP=1"
if /i "%~1"=="/SKIPAPACHE" set "SKIPAPACHE=1"
if /i "%~1"=="/STOPMYSQL"  set "STOPMYSQL=1"
shift
goto parse
:parsed

rem --- Marca de tiempo y carpeta de respaldo (fuera de C:\xampp) -------------
set "STAMP="
for /f %%T in ('powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-Date -Format yyyyMMdd-HHmmss"') do set "STAMP=%%T"
if not defined STAMP set "STAMP=%RANDOM%%RANDOM%"
set "BKROOT=%LOCALAPPDATA%\xampp-repair-backup"
if defined XAMPP_REPAIR_BACKUP_DIR set "BKROOT=%XAMPP_REPAIR_BACKUP_DIR%"
set "BK=%BKROOT%\%STAMP%"

echo ==== Reparacion de XAMPP para Windows 11 (cuenta sin administrador) ====

rem ==========================================================================
rem  1. Contexto de la cuenta
rem ==========================================================================
echo.
echo [1] Contexto de la cuenta
echo    Usuario: %USERDOMAIN%\%USERNAME%
net session >nul 2>&1
if errorlevel 1 (
    echo    [OK]    Sesion sin privilegios de administrador. No se requiere la contrasena de administrador.
) else (
    echo    [INFO]  La sesion actual esta elevada ^(no es necesario^).
)

rem ==========================================================================
rem  2. Restricciones de CMD y PowerShell
rem ==========================================================================
echo.
echo [2] Diagnostico de restricciones de CMD y PowerShell
call :chk_disablecmd HKCU
call :chk_disablecmd HKLM
echo    Politicas de ejecucion de PowerShell por ambito:
powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-ExecutionPolicy -List | ForEach-Object { '      {0,-15} {1}' -f $_.Scope, $_.ExecutionPolicy }"
powershell -NoProfile -ExecutionPolicy Bypass -Command "if ($ExecutionContext.SessionState.LanguageMode -ne 'FullLanguage') { Write-Host '   [AVISO] PowerShell en modo de lenguaje restringido (AppLocker/WDAC).' }"

rem ==========================================================================
rem  3. Finalizar procesos y servicios de XAMPP (solo los ubicados en C:\xampp)
rem ==========================================================================
echo.
echo [3] Finalizacion de procesos y servicios de XAMPP
powershell -NoProfile -ExecutionPolicy Bypass -Command "$r='%XAMPP%\'; $p=@(Get-CimInstance Win32_Process | Where-Object { $_.ExecutablePath -and $_.ExecutablePath.StartsWith($r,[StringComparison]::OrdinalIgnoreCase) } | Sort-Object { $_.Name -ne 'xampp-control.exe' }); if ($p.Count -eq 0) { Write-Host '   [OK]    No hay procesos de XAMPP en ejecucion.' } else { foreach ($x in $p) { try { Stop-Process -Id $x.ProcessId -Force -ErrorAction Stop; Write-Host ('   [OK]    Finalizado {0} (PID {1})' -f $x.Name,$x.ProcessId) } catch { Write-Host ('   [AVISO] No se pudo finalizar {0}: {1}' -f $x.Name,$_.Exception.Message) } } }"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$m='%XAMPP%'; $s=@(Get-CimInstance Win32_Service | Where-Object { $_.PathName -and $_.PathName -like ('*'+$m+'\*') }); if ($s.Count -eq 0) { Write-Host '   [OK]    Sin servicios de Windows registrados desde C:\xampp.' } else { foreach ($x in $s) { if ($x.State -eq 'Running') { try { Stop-Service -Name $x.Name -Force -ErrorAction Stop; Write-Host ('   [OK]    Servicio {0} detenido' -f $x.Name) } catch { Write-Host ('   [AVISO] El servicio {0} exige administrador para detenerse.' -f $x.Name) } } else { Write-Host ('   [INFO]  Servicio {0} detenido.' -f $x.Name) } } }"

rem ==========================================================================
rem  4. Habilitar ejecucion de scripts (PowerShell y CMD)
rem ==========================================================================
echo.
echo [4] Habilitacion de ejecucion de scripts
powershell -NoProfile -ExecutionPolicy Bypass -Command "try { Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force -ErrorAction Stop; Write-Host '   [OK]    Politica de ejecucion (CurrentUser) = RemoteSigned' } catch { Write-Host ('   [AVISO] ' + $_.Exception.Message) }"
powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-ChildItem -LiteralPath '%PROJECT_DIR%' -Recurse -File -ErrorAction SilentlyContinue | Unblock-File -ErrorAction SilentlyContinue; Write-Host '   [OK]    Archivos del proyecto desbloqueados (Unblock-File)'"
cmd /c "echo    [OK]    cmd.exe ejecuta comandos correctamente"

rem ==========================================================================
rem  5.1 Verificar la instalacion en C:\xampp
rem ==========================================================================
echo.
echo [5.1] Verificacion de la instalacion en %XAMPP%
if not exist "%XAMPP%\" goto err_noxampp
for %%F in (xampp-control.exe mysql\bin\mysqld.exe mysql\bin\mysql.exe mysql\bin\mysqladmin.exe apache\bin\httpd.exe) do (
    if not exist "%XAMPP%\%%F" (
        echo    [ERROR] Falta %XAMPP%\%%F
        goto err_incompleta
    )
)
if not exist "%XAMPP%\phpMyAdmin\" goto err_incompleta
for %%D in (mysql mysql\bin phpMyAdmin) do (
    (type nul > "%XAMPP%\%%D\.write-test.tmp") 2>nul
    if errorlevel 1 (
        set "BADDIR=%%D"
        goto err_permisos
    )
    del /f /q "%XAMPP%\%%D\.write-test.tmp" >nul 2>&1
)
echo    [OK]    Instalacion completa y con permisos de escritura.

rem ==========================================================================
rem  5.2 Verificar que la instalacion no este duplicada
rem ==========================================================================
echo.
echo [5.2] Verificacion de instalaciones duplicadas
set "PF86=%ProgramFiles(x86)%"
for %%D in (C D E F G H I J K L) do (
    if exist "%%D:\" (
        for /d %%P in ("%%D:\xampp*") do call :chkdup "%%~fP"
    )
)
for /d %%P in ("%ProgramFiles%\xampp*") do call :chkdup "%%~fP"
for /d %%P in ("%PF86%\xampp*") do call :chkdup "%%~fP"
for /d %%P in ("%USERPROFILE%\xampp*") do call :chkdup "%%~fP"
for /d %%P in ("%USERPROFILE%\Desktop\xampp*") do call :chkdup "%%~fP"
for /d %%P in ("%USERPROFILE%\Downloads\xampp*") do call :chkdup "%%~fP"
if exist "%XAMPP%\xampp\xampp-control.exe" (
    echo    [DUPLICADA] %XAMPP%\xampp ^(instalacion anidada^)
    set /a DUPS+=1
)
if %DUPS% GTR 0 (
    if not defined ALLOWDUP goto err_dup
    echo    [AVISO] Duplicadas ignoradas por /ALLOWDUP.
) else (
    echo    [OK]    No existen instalaciones duplicadas.
)

rem ==========================================================================
rem  5.3 Reemplazar C:\xampp\mysql\data por data.zip
rem ==========================================================================
echo.
echo [5.3] Reemplazo de %XAMPP%\mysql\data por data.zip
if not exist "%RES%\data.zip" (
    echo    [ERROR] No se encontro %RES%\data.zip
    goto fin_error
)
set "STG=%TEMP%\xampp-repair-%STAMP%"
mkdir "%STG%" >nul 2>&1
echo    Descomprimiendo data.zip en una carpeta temporal de validacion...
tar -xf "%RES%\data.zip" -C "%STG%"
if errorlevel 1 (
    echo    [ERROR] No se pudo descomprimir data.zip con tar.exe
    goto fin_error
)
if exist "%STG%\data\mysql\" (set "SRC=%STG%\data") else (set "SRC=%STG%")
if not exist "%SRC%\mysql\" goto err_zip
if not exist "%SRC%\ibdata1" goto err_zip

set "BACKED="
if exist "%XAMPP%\mysql\data\" (
    if defined NOBACKUP (
        rmdir /s /q "%XAMPP%\mysql\data"
        echo    [OK]    Carpeta data anterior eliminada ^(sin respaldo^).
    ) else (
        mkdir "%BK%" >nul 2>&1
        robocopy "%XAMPP%\mysql\data" "%BK%\data" /E /MOVE /R:1 /W:1 /NFL /NDL /NJH /NJS /NP >nul
        if errorlevel 8 goto err_backup
        rmdir /s /q "%XAMPP%\mysql\data" >nul 2>&1
        set "BACKED=1"
        echo    [OK]    Carpeta data anterior retirada de C:\xampp y conservada en: %BK%\data
    )
)
robocopy "%SRC%" "%XAMPP%\mysql\data" /E /MOVE /R:1 /W:1 /NFL /NDL /NJH /NJS /NP >nul
if errorlevel 8 goto err_data_rollback
if not exist "%XAMPP%\mysql\data\mysql\" goto err_data_rollback
rmdir /s /q "%STG%" >nul 2>&1
echo    [OK]    Nueva carpeta data instalada en %XAMPP%\mysql\data

rem ==========================================================================
rem  5.4 Reemplazar my.ini      5.5 Reemplazar config.inc.php
rem ==========================================================================
echo.
echo [5.4] Reemplazo de %XAMPP%\mysql\bin\my.ini
call :replace_file "%RES%\my.ini" "%XAMPP%\mysql\bin\my.ini"
if errorlevel 1 goto fin_error

echo.
echo [5.5] Reemplazo de %XAMPP%\phpMyAdmin\config.inc.php
set "RESCFG=%RES%\config.inc.php"
if not exist "%RESCFG%" set "RESCFG=%RES%\config_inc.php"
call :replace_file "%RESCFG%" "%XAMPP%\phpMyAdmin\config.inc.php"
if errorlevel 1 goto fin_error

rem ==========================================================================
rem  5.6 PATH del usuario: C:\xampp\mysql\bin
rem ==========================================================================
echo.
echo [5.6] PATH del usuario: %XAMPP%\mysql\bin
call :addpath
set "PATH=%PATH%;%XAMPP%\mysql\bin"

rem ==========================================================================
rem  5.7 Verificar el acceso a MySQL
rem ==========================================================================
echo.
echo [5.7] Verificacion de acceso a MySQL ^(puerto %MYSQL_PORT%^)
netstat -ano | findstr /R /C:":%MYSQL_PORT% .*LISTENING" >nul
if not errorlevel 1 (
    echo    [ERROR] El puerto %MYSQL_PORT% ya esta en uso. Liberelo y repita el proceso.
    netstat -ano | findstr /R /C:":%MYSQL_PORT% .*LISTENING"
    goto fin_error
)
echo    Iniciando mysqld con %XAMPP%\mysql\bin\my.ini...
start "" /B "%XAMPP%\mysql\bin\mysqld.exe" --defaults-file="%XAMPP%\mysql\bin\my.ini" --standalone >nul 2>&1
set /a N=0
:wait_mysql
netstat -ano | findstr /R /C:":%MYSQL_PORT% .*LISTENING" >nul
if not errorlevel 1 goto mysql_up
set /a N+=1
if %N% GEQ 45 goto mysql_fail
ping -n 2 127.0.0.1 >nul
goto wait_mysql
:mysql_fail
echo    [ERROR] mysqld no quedo escuchando en el puerto %MYSQL_PORT%.
if exist "%XAMPP%\mysql\data\mysql_error.log" (
    echo    Ultimas lineas de mysql_error.log:
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-Content -LiteralPath '%XAMPP%\mysql\data\mysql_error.log' -Tail 15 | ForEach-Object { '      ' + $_ }"
)
goto fin_error
:mysql_up
echo    [OK]    mysqld escucha en el puerto %MYSQL_PORT%.
"%XAMPP%\mysql\bin\mysql.exe" -u root -h localhost -P %MYSQL_PORT% -D mysql --connect-timeout=10 -e "SELECT CURRENT_USER() AS usuario, DATABASE() AS base_datos, VERSION() AS version; SHOW DATABASES;"
if errorlevel 1 (
    echo    [ERROR] El cliente mysql no pudo autenticarse en el servidor.
    goto fin_error
)
echo    [OK]    Acceso a MySQL verificado ^(usuario root, sin contrasena, base de datos mysql^).

rem ==========================================================================
rem  Diagnostico complementario de Apache (no modifica archivos)
rem ==========================================================================
if defined SKIPAPACHE goto after_apache
echo.
echo [+] Diagnostico complementario de Apache
set "WEBPORT=80"
for /f "tokens=2" %%P in ('findstr /R /B /C:"Listen [0-9]" "%XAMPP%\apache\conf\httpd.conf" 2^>nul') do set "WEBPORT=%%P"
set "APBLOCK="
for %%P in (%WEBPORT% 443) do (
    netstat -ano | findstr /R /C:":%%P .*LISTENING" >nul
    if not errorlevel 1 (
        echo    [AVISO] Puerto %%P ocupado ^(PID en la ultima columna^). Apache no podra iniciar:
        netstat -ano | findstr /R /C:":%%P .*LISTENING"
        set "APBLOCK=1"
    ) else (
        echo    [OK]    Puerto %%P libre.
    )
)
if defined APBLOCK goto after_apache
start "" /B "%XAMPP%\apache\bin\httpd.exe" >nul 2>&1
ping -n 6 127.0.0.1 >nul
netstat -ano | findstr /R /C:":%WEBPORT% .*LISTENING" >nul
if errorlevel 1 (
    echo    [AVISO] httpd.exe no quedo escuchando. Revise %XAMPP%\apache\logs\error.log
) else (
    for /f %%C in ('curl.exe -s -o nul -w "%%{http_code}" http://localhost:%WEBPORT%/') do echo    [OK]    Apache responde HTTP %%C en el puerto %WEBPORT%.
)
powershell -NoProfile -ExecutionPolicy Bypass -Command "$r='%XAMPP%\'; Get-CimInstance Win32_Process | Where-Object { $_.Name -eq 'httpd.exe' -and $_.ExecutablePath -and $_.ExecutablePath.StartsWith($r,[StringComparison]::OrdinalIgnoreCase) } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }"
:after_apache

if defined STOPMYSQL (
    "%XAMPP%\mysql\bin\mysqladmin.exe" -u root -h 127.0.0.1 -P %MYSQL_PORT% shutdown
    echo    [OK]    MySQL detenido de forma ordenada.
)

echo.
echo ==== Proceso finalizado sin errores ====
if defined BACKED echo Respaldo de lo reemplazado: %BK%
echo.
echo Para la verificacion manual abra una terminal NUEVA y ejecute:
echo    mysql -u root -p -h localhost -P %MYSQL_PORT% -D mysql
echo    ^(cuando solicite la contrasena, presione Enter: no tiene^)
endlocal & exit /b 0

rem ==========================================================================
rem  Rutas de error
rem ==========================================================================
:err_noxampp
echo    [ERROR] No existe %XAMPP%. XAMPP debe estar instalado exactamente en esa ruta.
goto fin_error
:err_incompleta
echo    [ERROR] La instalacion de %XAMPP% esta incompleta.
goto fin_error
:err_permisos
echo    [ERROR] Esta cuenta no tiene permiso de escritura en %XAMPP%\%BADDIR%.
echo            Sin administrador no es posible continuar; solicite permisos de modificacion sobre C:\xampp.
goto fin_error
:err_dup
echo    [ERROR] Se detectaron instalaciones duplicadas de XAMPP. Retirelas o use /ALLOWDUP bajo su responsabilidad.
goto fin_error
:err_zip
echo    [ERROR] data.zip no contiene mysql\ e ibdata1: no parece un directorio de datos valido.
rmdir /s /q "%STG%" >nul 2>&1
goto fin_error
:err_backup
echo    [ERROR] No se pudo mover la carpeta data actual al respaldo. No se realizo ningun cambio adicional.
rmdir /s /q "%STG%" >nul 2>&1
goto fin_error
:err_data_rollback
echo    [ERROR] Fallo la instalacion de la nueva carpeta data.
if defined BACKED (
    if exist "%BK%\data\" (
        rmdir /s /q "%XAMPP%\mysql\data" >nul 2>&1
        robocopy "%BK%\data" "%XAMPP%\mysql\data" /E /MOVE /R:1 /W:1 /NFL /NDL /NJH /NJS /NP >nul
        echo    [AVISO] Se restauro la carpeta data original desde el respaldo.
    )
)
goto fin_error
:fin_error
echo.
echo ==== El proceso termino con errores. Revise los mensajes anteriores. ====
endlocal & exit /b 1

rem ==========================================================================
rem  Subrutinas
rem ==========================================================================
:chk_disablecmd
rem %1 = HKCU | HKLM. DisableCMD: 0 = permitido, 1 = CMD y .bat bloqueados, 2 = solo CMD interactivo bloqueado.
reg query "%~1\Software\Policies\Microsoft\Windows\System" /v DisableCMD >nul 2>&1
if errorlevel 1 (
    echo    [OK]    %~1: sin directiva DisableCMD.
    exit /b 0
)
for /f "tokens=3" %%V in ('reg query "%~1\Software\Policies\Microsoft\Windows\System" /v DisableCMD 2^>nul ^| findstr /i "DisableCMD"') do (
    if "%%V"=="0x0" (
        echo    [OK]    %~1: DisableCMD = 0
    ) else (
        echo    [AVISO] %~1: DisableCMD = %%V ^(CMD restringido por directiva; no puede cambiarse sin administrador^).
    )
)
exit /b 0

:chkdup
if /i "%~1"=="%XAMPP%" exit /b 0
if exist "%~1\xampp-control.exe" (
    echo    [DUPLICADA] %~1
    set /a DUPS+=1
)
exit /b 0

:replace_file
rem %1 = origen, %2 = destino
if not exist "%~1" (
    echo    [ERROR] No se encontro el recurso %~1
    exit /b 1
)
if exist "%~2" (
    if not defined NOBACKUP (
        mkdir "%BK%" >nul 2>&1
        copy /y "%~2" "%BK%\%~nx2" >nul
        set "BACKED=1"
    )
    attrib -r "%~2" >nul 2>&1
    del /f /q "%~2"
)
copy /y "%~1" "%~2" >nul
if errorlevel 1 (
    echo    [ERROR] No se pudo copiar %~nx1 hacia %~2
    exit /b 1
)
fc /b "%~1" "%~2" >nul
if errorlevel 1 (
    echo    [ERROR] La comparacion binaria de %~nx2 fallo.
    exit /b 1
)
echo    [OK]    %~nx2 reemplazado y verificado ^(comparacion binaria^).
exit /b 0

:addpath
rem Conserva el tipo REG_EXPAND_SZ y las variables sin expandir (p. ej. %%USERPROFILE%%).
setlocal EnableDelayedExpansion
set "USERPATH="
for /f "tokens=2,*" %%A in ('reg query "HKCU\Environment" /v Path 2^>nul ^| findstr /i /c:"REG_"') do set "USERPATH=%%B"
if defined USERPATH if "!USERPATH:~-1!"==";" set "USERPATH=!USERPATH:~0,-1!"
set "TEST=;!USERPATH!;"
set "CHK=!TEST:;%XAMPP%\mysql\bin;=!"
if not "!CHK!"=="!TEST!" (
    echo    [OK]    %XAMPP%\mysql\bin ya figura en el PATH del usuario.
    endlocal
    exit /b 0
)
if defined USERPATH (set "NEWPATH=!USERPATH!;%XAMPP%\mysql\bin") else (set "NEWPATH=%XAMPP%\mysql\bin")
reg add "HKCU\Environment" /v Path /t REG_EXPAND_SZ /d "!NEWPATH!" /f >nul
if errorlevel 1 (
    echo    [ERROR] No se pudo escribir HKCU\Environment\Path.
    endlocal
    exit /b 1
)
rem setx difunde WM_SETTINGCHANGE; luego se elimina la variable auxiliar.
setx XAMPP_REPAIR_NOTIFY 1 >nul 2>&1
reg delete "HKCU\Environment" /v XAMPP_REPAIR_NOTIFY /f >nul 2>&1
echo    [OK]    %XAMPP%\mysql\bin agregado al PATH del usuario ^(abra una terminal nueva^).
endlocal
exit /b 0
