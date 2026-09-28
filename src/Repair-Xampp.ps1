#Requires -Version 5.1
<#
.SYNOPSIS
    Repara XAMPP (Apache y MySQL/MariaDB) en Windows 11 desde una cuenta local
    SIN privilegios de administrador.

.DESCRIPTION
    Ejecuta, en orden, las siguientes fases:
      1. Contexto de la cuenta (no solicita ni requiere la contraseña de administrador).
      2. Diagnóstico de restricciones de PowerShell y CMD.
      3. Finalización de procesos y servicios de XAMPP (solo los ubicados en C:\xampp).
      4. Habilitación de scripts para el usuario actual (ámbito CurrentUser).
      5. Cambios únicos sobre C:\xampp:
         5.1 Verificar la instalación en C:\xampp.
         5.2 Verificar que no existan instalaciones duplicadas.
         5.3 Reemplazar C:\xampp\mysql\data con static\data.zip.
         5.4 Reemplazar C:\xampp\mysql\bin\my.ini.
         5.5 Reemplazar C:\xampp\phpMyAdmin\config.inc.php.
         5.6 Agregar C:\xampp\mysql\bin al PATH del usuario actual.
         5.7 Iniciar MySQL y Apache, y verificar el acceso a MySQL (puerto 3307,
             usuario root sin contraseña), abriendo al final el cliente interactivo.

    Limitaciones deliberadas: el script NO evade directivas de grupo (GPO), AppLocker
    ni ningún control administrativo; si alguno impide la operación, lo informa.

.PARAMETER ResourcesPath
    Carpeta con data.zip, my.ini y config.inc.php. Por defecto: ..\static

.PARAMETER NoBackup
    Elimina definitivamente lo reemplazado en lugar de conservar una copia de
    respaldo (fuera de C:\xampp).

.PARAMETER AllowDuplicates
    Continúa aunque se detecten otras instalaciones de XAMPP (no recomendado).

.PARAMETER SkipApache
    Omite el diagnóstico y la prueba de arranque de Apache.

.PARAMETER StopServices
    Detiene MySQL y Apache al finalizar. Por defecto ambos quedan en ejecución y
    no se abre el cliente interactivo si se usa este conmutador.

.PARAMETER NoNativeAio
    Inicia mysqld directamente con --innodb-use-native-aio=0 (solo en la línea de
    comandos, sin modificar my.ini). Si mysqld falla con la configuración normal, el
    script lo reintenta automáticamente así tras restablecer data.zip.

.PARAMETER PersistNativeAio
    Si mysqld solo inicia con --innodb-use-native-aio=0, agrega innodb_use_native_aio=0
    a la sección [mysqld] del my.ini instalado (cambio explícito y opcional; el panel de
    XAMPP necesita esta línea para poder iniciar MySQL en ese caso).

.PARAMETER NoShell
    No abre al final el cliente interactivo 'mysql -u root -p -h localhost -P 3307 -D mysql'.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\src\Repair-Xampp.ps1

.NOTES
    Autor : Ingeniero Andrés Felipe Gutiérrez Rivera
    Versión: 1.0.0
    Licencia: MIT
#>
[CmdletBinding()]
param(
    [string]$ResourcesPath,
    [switch]$NoBackup,
    [switch]$AllowDuplicates,
    [switch]$SkipApache,
    [switch]$StopServices,
    [switch]$NoNativeAio,
    [switch]$PersistNativeAio,
    [switch]$NoShell
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Resolución robusta de rutas del proyecto. $PSScriptRoot puede estar vacío si el
# script no se invoca con -File (p. ej. "Ejecutar con PowerShell" o pegado en consola).
# ---------------------------------------------------------------------------
$script:DirScript = $null
if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) { $script:DirScript = $PSScriptRoot }
elseif ($MyInvocation.MyCommand.Path) { $script:DirScript = Split-Path -Parent $MyInvocation.MyCommand.Path }
else { $script:DirScript = (Get-Location).Path }

$script:DirProyecto = Split-Path -Parent $script:DirScript
if ([string]::IsNullOrWhiteSpace($ResourcesPath)) {
    $ResourcesPath = Join-Path $script:DirProyecto 'static'
    # Si se ejecutó desde la raíz del proyecto en lugar de src\, se ajusta.
    if (-not (Test-Path -LiteralPath (Join-Path $ResourcesPath 'data.zip'))) {
        $alterna = Join-Path (Get-Location).Path 'static'
        if (Test-Path -LiteralPath (Join-Path $alterna 'data.zip')) {
            $ResourcesPath = $alterna
            $script:DirProyecto = (Get-Location).Path
        }
    }
}

# ---------------------------------------------------------------------------
# Constantes y estado global
# ---------------------------------------------------------------------------
$script:RaizXampp   = 'C:\xampp'
$script:PuertoMySql = 3307
$script:Resumen     = New-Object System.Collections.Generic.List[object]
$script:DirRespaldo = $null
$script:MySqlIniciadoPorScript = $false
$script:MySqlAio0 = $false

# ---------------------------------------------------------------------------
# Utilidades de salida
# ---------------------------------------------------------------------------
function Write-Paso {
    param([string]$Numero, [string]$Texto)
    Write-Host ''
    Write-Host ('[{0}] {1}' -f $Numero, $Texto) -ForegroundColor Cyan
}
function Write-Ok    { param([string]$Texto) Write-Host ('   [OK]    {0}' -f $Texto) -ForegroundColor Green }
function Write-Aviso { param([string]$Texto) Write-Host ('   [AVISO] {0}' -f $Texto) -ForegroundColor Yellow }
function Write-Info  { param([string]$Texto) Write-Host ('   {0}' -f $Texto) }

function Add-Resumen {
    param([string]$Paso, [string]$Estado, [string]$Detalle)
    $script:Resumen.Add([pscustomobject]@{ Paso = $Paso; Estado = $Estado; Detalle = $Detalle })
}

# ---------------------------------------------------------------------------
# Utilidades generales
# ---------------------------------------------------------------------------
function Test-EsAdministrador {
    $identidad = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identidad)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-DirectorioRespaldo {
    # Crea (una sola vez) la carpeta de respaldo FUERA de C:\xampp.
    if (-not $script:DirRespaldo) {
        $base = $env:XAMPP_REPAIR_BACKUP_DIR
        if ([string]::IsNullOrWhiteSpace($base)) {
            $base = Join-Path $env:LOCALAPPDATA 'xampp-repair-backup'
        }
        $script:DirRespaldo = Join-Path $base (Get-Date -Format 'yyyyMMdd-HHmmss')
        New-Item -ItemType Directory -Path $script:DirRespaldo -Force | Out-Null
    }
    return $script:DirRespaldo
}

function Test-EscrituraDirectorio {
    param([string]$Ruta)
    $prueba = Join-Path $Ruta ('.write-test-{0}.tmp' -f [guid]::NewGuid().ToString('N'))
    try {
        New-Item -ItemType File -Path $prueba -ErrorAction Stop | Out-Null
        Remove-Item -LiteralPath $prueba -Force -ErrorAction Stop
        return $true
    }
    catch { return $false }
}

function Get-EscuchaPuerto {
    # Devuelve los PID que escuchan en un puerto TCP (no requiere administrador).
    param([int]$Puerto)
    $conexiones = @(Get-NetTCPConnection -State Listen -LocalPort $Puerto -ErrorAction SilentlyContinue)
    return @($conexiones | ForEach-Object { $_.OwningProcess } | Select-Object -Unique)
}

function Get-NombreProceso {
    param([int]$IdProceso)
    if ($IdProceso -eq 4) { return 'System (http.sys / IIS / servicio de Windows)' }
    try { return (Get-Process -Id $IdProceso -ErrorAction Stop).ProcessName }
    catch { return 'desconocido (acceso denegado)' }
}

function Wait-Puerto {
    param([int]$Puerto, [int]$Segundos = 45, [System.Diagnostics.Process]$Proceso = $null)
    $limite = (Get-Date).AddSeconds($Segundos)
    while ((Get-Date) -lt $limite) {
        $cliente = New-Object System.Net.Sockets.TcpClient
        try {
            $asincrono = $cliente.BeginConnect('127.0.0.1', $Puerto, $null, $null)
            if ($asincrono.AsyncWaitHandle.WaitOne(500) -and $cliente.Connected) { return $true }
        }
        catch { }
        finally { $cliente.Close() }
        if ($Proceso -and $Proceso.HasExited) { return $false }
        Start-Sleep -Milliseconds 500
    }
    return $false
}

function Show-PrimerasLineas {
    param([string]$Archivo, [int]$Cantidad = 12)
    if (Test-Path -LiteralPath $Archivo) {
        Write-Info ('Primeras líneas de {0}:' -f $Archivo)
        Get-Content -LiteralPath $Archivo -TotalCount $Cantidad -ErrorAction SilentlyContinue |
            ForEach-Object { Write-Host ('      ' + $_) -ForegroundColor DarkGray }
    }
}

function Invoke-Nativo {
    # Ejecuta un binario nativo capturando salida y código de retorno sin que
    # PowerShell 5.1 convierta stderr en excepciones terminantes.
    param([string]$Exe, [string[]]$Argumentos)
    $previo = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $salida = & $Exe @Argumentos 2>&1 | ForEach-Object { "$_" }
        $codigo = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $previo }
    return [pscustomobject]@{ Codigo = $codigo; Salida = ((@($salida) -join [Environment]::NewLine).Trim()) }
}

function Show-UltimasLineas {
    param([string]$Archivo, [int]$Cantidad = 15)
    if (Test-Path -LiteralPath $Archivo) {
        Write-Info ('Últimas líneas de {0}:' -f $Archivo)
        Get-Content -LiteralPath $Archivo -Tail $Cantidad -ErrorAction SilentlyContinue |
            ForEach-Object { Write-Host ('      ' + $_) -ForegroundColor DarkGray }
    }
}

# ---------------------------------------------------------------------------
# Fase 2: restricciones de PowerShell y CMD
# ---------------------------------------------------------------------------
function Test-Restricciones {
    $hallazgos = 0

    Write-Info 'Políticas de ejecución por ámbito:'
    $ambitos = @(Get-ExecutionPolicy -List)
    foreach ($a in $ambitos) { Write-Info ('   {0,-15} {1}' -f $a.Scope, $a.ExecutionPolicy) }

    foreach ($a in $ambitos) {
        if (($a.Scope -in 'MachinePolicy', 'UserPolicy') -and ($a.ExecutionPolicy -ne 'Undefined')) {
            Write-Aviso ('Una directiva de grupo (GPO) define la política en {0}: {1}. No puede modificarse sin administrador.' -f $a.Scope, $a.ExecutionPolicy)
            $hallazgos++
        }
    }

    $modo = $ExecutionContext.SessionState.LanguageMode
    if ($modo -eq 'FullLanguage') { Write-Ok 'Modo de lenguaje de PowerShell: FullLanguage.' }
    else {
        Write-Aviso ('Modo de lenguaje restringido ({0}): posible AppLocker/WDAC.' -f $modo)
        $hallazgos++
    }

    foreach ($colmena in 'HKCU', 'HKLM') {
        $clave = '{0}:\Software\Policies\Microsoft\Windows\System' -f $colmena
        $valor = Get-ItemProperty -Path $clave -Name 'DisableCMD' -ErrorAction SilentlyContinue
        if ($valor -and ($valor.PSObject.Properties.Name -contains 'DisableCMD')) {
            $n = [int]$valor.DisableCMD
            if ($n -ne 0) {
                Write-Aviso ('{0}: DisableCMD = {1} (el símbolo del sistema está restringido por directiva).' -f $colmena, $n)
                $hallazgos++
            }
            else { Write-Ok ('{0}: DisableCMD = 0.' -f $colmena) }
        }
    }

    $prueba = & (Join-Path $env:SystemRoot 'System32\cmd.exe') /c 'echo CMD_OPERATIVO' 2>&1
    if ("$prueba" -match 'CMD_OPERATIVO') { Write-Ok 'cmd.exe se ejecuta correctamente.' }
    else {
        Write-Aviso 'cmd.exe no devolvió la salida esperada.'
        $hallazgos++
    }

    return $hallazgos
}

# ---------------------------------------------------------------------------
# Fase 3: finalizar procesos y servicios de XAMPP
# ---------------------------------------------------------------------------
function Get-ProcesosXampp {
    $prefijo = $script:RaizXampp.TrimEnd('\') + '\'
    return @(Get-CimInstance -ClassName Win32_Process -ErrorAction SilentlyContinue |
        Where-Object { $_.ExecutablePath -and $_.ExecutablePath.StartsWith($prefijo, [StringComparison]::OrdinalIgnoreCase) })
}

function Stop-ProcesosXampp {
    param([switch]$Silencioso)
    $procesos = Get-ProcesosXampp
    # El panel de control se cierra primero para que no reinicie los módulos.
    $ordenados = @($procesos | Sort-Object { $_.Name -ne 'xampp-control.exe' })
    foreach ($p in $ordenados) {
        try {
            Stop-Process -Id $p.ProcessId -Force -ErrorAction Stop
            if (-not $Silencioso) { Write-Ok ('Finalizado {0} (PID {1}).' -f $p.Name, $p.ProcessId) }
        }
        catch {
            if (-not $Silencioso) { Write-Aviso ('No se pudo finalizar {0} (PID {1}): {2}' -f $p.Name, $p.ProcessId, $_.Exception.Message) }
        }
    }
    Start-Sleep -Seconds 2
    return @(Get-ProcesosXampp)
}

function Stop-ServiciosXampp {
    $marca = $script:RaizXampp.TrimEnd('\')
    $servicios = @(Get-CimInstance -ClassName Win32_Service -ErrorAction SilentlyContinue |
        Where-Object { $_.PathName -and ($_.PathName -like ('*' + $marca + '\*')) })
    if ($servicios.Count -eq 0) { Write-Ok 'No hay servicios de Windows registrados desde C:\xampp.'; return 0 }
    $pendientes = 0
    foreach ($s in $servicios) {
        Write-Info ('Servicio detectado: {0} ({1}), estado {2}.' -f $s.Name, $s.DisplayName, $s.State)
        if ($s.State -eq 'Running') {
            try { Stop-Service -Name $s.Name -Force -ErrorAction Stop; Write-Ok ('Servicio {0} detenido.' -f $s.Name) }
            catch {
                Write-Aviso ('No se pudo detener el servicio {0}: detener servicios exige administrador.' -f $s.Name)
                $pendientes++
            }
        }
    }
    return $pendientes
}

# ---------------------------------------------------------------------------
# Fase 4: habilitar scripts
# ---------------------------------------------------------------------------
function Enable-EjecucionScripts {
    try {
        Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force -ErrorAction Stop
        Write-Ok 'Política de ejecución (CurrentUser) = RemoteSigned.'
    }
    catch {
        Write-Aviso ('No fue posible fijar la política de usuario: {0}' -f $_.Exception.Message)
    }
    Write-Info ('Política efectiva actual: {0}' -f (Get-ExecutionPolicy))

    # Elimina la marca de descarga (Zone.Identifier) de los archivos del proyecto.
    try {
        $raizProyecto = $script:DirProyecto
        Get-ChildItem -LiteralPath $raizProyecto -Recurse -File -ErrorAction SilentlyContinue |
            Unblock-File -ErrorAction SilentlyContinue
        Write-Ok 'Archivos del proyecto desbloqueados (Unblock-File).'
    }
    catch { Write-Aviso 'No se pudo ejecutar Unblock-File sobre el proyecto.' }
    Write-Info 'Los archivos .bat/.cmd no requieren política de ejecución; solo dependen de que cmd.exe no esté restringido.'
}

# ---------------------------------------------------------------------------
# Fase 5.1 y 5.2: instalación y duplicados
# ---------------------------------------------------------------------------
function Test-InstalacionXampp {
    if (-not (Test-Path -LiteralPath $script:RaizXampp -PathType Container)) {
        throw ('No existe {0}. XAMPP debe estar instalado exactamente en esa ruta.' -f $script:RaizXampp)
    }
    $requeridos = @('xampp-control.exe', 'mysql\bin\mysqld.exe', 'mysql\bin\mysql.exe', 'mysql\bin\mysqladmin.exe',
                    'apache\bin\httpd.exe', 'phpMyAdmin')
    $faltantes = @($requeridos | Where-Object { -not (Test-Path -LiteralPath (Join-Path $script:RaizXampp $_)) })
    if ($faltantes.Count -gt 0) {
        throw ('La instalación de C:\xampp está incompleta. Faltan: {0}' -f ($faltantes -join ', '))
    }
    foreach ($carpeta in 'mysql', 'mysql\bin', 'phpMyAdmin') {
        $ruta = Join-Path $script:RaizXampp $carpeta
        if (-not (Test-EscrituraDirectorio -Ruta $ruta)) {
            throw ('Esta cuenta no tiene permiso de escritura en {0}. Sin administrador no es posible continuar de forma legítima; solicite a quien administre el equipo que otorgue permisos de modificación sobre C:\xampp.' -f $ruta)
        }
    }
}

function Get-InstalacionesDuplicadas {
    $candidatos = New-Object System.Collections.Generic.List[string]
    $unidades = @([System.IO.DriveInfo]::GetDrives() | Where-Object { $_.DriveType -eq 'Fixed' -and $_.IsReady })
    foreach ($u in $unidades) {
        Get-ChildItem -LiteralPath $u.RootDirectory.FullName -Directory -Force -ErrorAction SilentlyContinue |
            ForEach-Object { $candidatos.Add($_.FullName) }
    }
    $bases = @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:USERPROFILE,
               [Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('MyDocuments'),
               (Join-Path $env:USERPROFILE 'Downloads'), $script:RaizXampp)
    foreach ($b in $bases) {
        if ($b -and (Test-Path -LiteralPath $b)) {
            $candidatos.Add($b)
            Get-ChildItem -LiteralPath $b -Directory -Force -ErrorAction SilentlyContinue |
                ForEach-Object { $candidatos.Add($_.FullName) }
        }
    }
    $normal = $script:RaizXampp.TrimEnd('\')
    $encontradas = foreach ($c in ($candidatos | Select-Object -Unique)) {
        $esXampp = (Test-Path -LiteralPath (Join-Path $c 'xampp-control.exe')) -or
                   (Test-Path -LiteralPath (Join-Path $c 'apache\bin\httpd.exe'))
        if ($esXampp -and ($c.TrimEnd('\') -ine $normal)) { $c }
    }
    return @($encontradas)
}

# ---------------------------------------------------------------------------
# Fase 5.3 a 5.5: reemplazos
# ---------------------------------------------------------------------------
function Restore-CarpetaData {
    $zip = Join-Path $ResourcesPath 'data.zip'
    if (-not (Test-Path -LiteralPath $zip)) { throw ('No se encontró {0}.' -f $zip) }

    $destino = Join-Path $script:RaizXampp 'mysql\data'
    $staging = Join-Path $env:TEMP ('xampp-repair-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $staging | Out-Null
    $respaldada = $null
    try {
        Write-Info 'Descomprimiendo data.zip en una carpeta temporal de validación...'
        Expand-Archive -LiteralPath $zip -DestinationPath $staging -Force

        $origen = Join-Path $staging 'data'
        if (-not (Test-Path -LiteralPath $origen -PathType Container)) { $origen = $staging }
        foreach ($imprescindible in 'mysql', 'ibdata1') {
            if (-not (Test-Path -LiteralPath (Join-Path $origen $imprescindible))) {
                throw ('data.zip no contiene "{0}"; el archivo no parece un directorio de datos válido.' -f $imprescindible)
            }
        }

        if (Test-Path -LiteralPath $destino) {
            if ($NoBackup) {
                Remove-Item -LiteralPath $destino -Recurse -Force
                Write-Ok 'Carpeta data anterior eliminada (sin respaldo).'
            }
            else {
                $nombreResp = 'data'; $n = 2
                while (Test-Path -LiteralPath (Join-Path (Get-DirectorioRespaldo) $nombreResp)) {
                    $nombreResp = 'data-intento{0}' -f $n; $n++
                }
                $respaldada = Join-Path (Get-DirectorioRespaldo) $nombreResp
                Move-Item -LiteralPath $destino -Destination $respaldada
                Write-Ok ('Carpeta data anterior retirada de C:\xampp y conservada en: {0}' -f $respaldada)
            }
        }

        try {
            Move-Item -LiteralPath $origen -Destination $destino
        }
        catch {
            if ($respaldada -and -not (Test-Path -LiteralPath $destino)) {
                Move-Item -LiteralPath $respaldada -Destination $destino
                Write-Aviso 'Se revirtió el cambio: se restauró la carpeta data original.'
            }
            throw
        }
        Write-Ok 'Nueva carpeta data instalada en C:\xampp\mysql\data.'
    }
    finally {
        Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Set-ArchivoReemplazo {
    param([string]$Origen, [string]$Destino, [string]$Etiqueta)
    if (-not (Test-Path -LiteralPath $Origen)) { throw ('No se encontró el recurso {0}.' -f $Origen) }

    if (Test-Path -LiteralPath $Destino) {
        if (-not $NoBackup) {
            Copy-Item -LiteralPath $Destino -Destination (Join-Path (Get-DirectorioRespaldo) (Split-Path -Leaf $Destino)) -Force
        }
        Set-ItemProperty -LiteralPath $Destino -Name IsReadOnly -Value $false
        Remove-Item -LiteralPath $Destino -Force
    }
    Copy-Item -LiteralPath $Origen -Destination $Destino -Force

    $hashOrigen  = (Get-FileHash -LiteralPath $Origen  -Algorithm SHA256).Hash
    $hashDestino = (Get-FileHash -LiteralPath $Destino -Algorithm SHA256).Hash
    if ($hashOrigen -ne $hashDestino) { throw ('La verificación SHA-256 de {0} falló.' -f $Etiqueta) }
    Write-Ok ('{0} reemplazado (SHA-256 verificado: {1}...).' -f $Etiqueta, $hashDestino.Substring(0, 12))
}

# ---------------------------------------------------------------------------
# Fase 5.6: PATH del usuario
# ---------------------------------------------------------------------------
function Add-RutaPathUsuario {
    param([string]$Ruta)
    $clave = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $true)
    if (-not $clave) { throw 'No se pudo abrir HKCU\Environment para escritura.' }
    try {
        # Se lee SIN expandir variables para conservar entradas como %USERPROFILE%.
        $actual = [string]$clave.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        $entradas = @($actual -split ';' | Where-Object { $_.Trim() -ne '' })
        $presente = @($entradas | Where-Object {
            ([Environment]::ExpandEnvironmentVariables($_)).TrimEnd('\') -ieq $Ruta.TrimEnd('\')
        })
        if ($presente.Count -gt 0) {
            Write-Ok ('{0} ya figura en el PATH del usuario.' -f $Ruta)
        }
        else {
            $nuevo = (@($entradas) + $Ruta) -join ';'
            $clave.SetValue('Path', $nuevo, [Microsoft.Win32.RegistryValueKind]::ExpandString)
            # Difunde WM_SETTINGCHANGE para que las nuevas terminales lean el cambio.
            [Environment]::SetEnvironmentVariable('XAMPP_REPAIR_NOTIFY', '1', 'User')
            [Environment]::SetEnvironmentVariable('XAMPP_REPAIR_NOTIFY', $null, 'User')
            Write-Ok ('{0} agregado al PATH del usuario (HKCU\Environment).' -f $Ruta)
        }
    }
    finally { $clave.Close() }

    if (($env:Path -split ';') -notcontains $Ruta) { $env:Path = $env:Path.TrimEnd(';') + ';' + $Ruta }

    $todos = @(Get-Command -Name mysql.exe -All -ErrorAction SilentlyContinue)
    if ($todos.Count -gt 1) {
        Write-Aviso 'Se detectaron varios mysql.exe en el PATH; el primero tiene prioridad:'
        $todos | ForEach-Object { Write-Info ('   ' + $_.Source) }
    }
}

# ---------------------------------------------------------------------------
# Fase 5.7: inicio de servicios (MySQL y Apache) y verificación de MySQL
# ---------------------------------------------------------------------------
function Start-MySqlServicio {
    $bin = Join-Path $script:RaizXampp 'mysql\bin'
    $puerto = $script:PuertoMySql
    $logMysql = Join-Path $script:RaizXampp 'mysql\data\mysql_error.log'

    $ocupado = @(Get-EscuchaPuerto -Puerto $puerto)
    if ($ocupado.Count -gt 0) {
        $detalle = ($ocupado | ForEach-Object { '{0} (PID {1})' -f (Get-NombreProceso -IdProceso $_), $_ }) -join ', '
        throw ('El puerto {0} ya está en uso por: {1}. Libérelo antes de continuar.' -f $puerto, $detalle)
    }

    $usarAio0 = [bool]$NoNativeAio
    while ($true) {
        $argumentos = @(('--defaults-file=' + (Join-Path $bin 'my.ini')), '--standalone')
        if ($usarAio0) {
            $argumentos += '--innodb-use-native-aio=0'
            Write-Aviso 'Modo diagnóstico: mysqld se inicia con --innodb-use-native-aio=0 (my.ini no se modifica).'
        }
        Write-Info 'Iniciando MySQL (mysqld) con C:\xampp\mysql\bin\my.ini...'
        $proceso = Start-Process -FilePath (Join-Path $bin 'mysqld.exe') `
            -ArgumentList $argumentos -WorkingDirectory $bin -WindowStyle Hidden -PassThru

        if (Wait-Puerto -Puerto $puerto -Segundos 45 -Proceso $proceso) {
            $script:MySqlIniciadoPorScript = $true
            $script:MySqlAio0 = $usarAio0
            Write-Ok ('MySQL iniciado y escuchando en el puerto {0}.' -f $puerto)
            return
        }

        $version = Invoke-Nativo -Exe (Join-Path $bin 'mysqld.exe') -Argumentos @('--version')
        Write-Aviso ('mysqld no quedó escuchando. Versión del servidor: {0}' -f $version.Salida)
        Show-PrimerasLineas -Archivo $logMysql
        Show-UltimasLineas  -Archivo $logMysql
        [void](Stop-ProcesosXampp -Silencioso)

        if ($usarAio0) {
            throw 'mysqld no inició ni siquiera con --innodb-use-native-aio=0. Envíe el contenido de mysql_error.log para continuar el diagnóstico.'
        }
        Write-Aviso 'Se restablece data.zip (para descartar restos del intento fallido) y se reintenta con --innodb-use-native-aio=0...'
        Restore-CarpetaData
        $usarAio0 = $true
    }
}

function Set-NativeAioPersistente {
    $ini = Join-Path $script:RaizXampp 'mysql\bin\my.ini'
    $texto = [System.IO.File]::ReadAllText($ini)
    if ($texto -match '(?im)^\s*innodb_use_native_aio') {
        Write-Info 'my.ini ya define innodb_use_native_aio; no se modifica.'
        return
    }
    $nl = [Environment]::NewLine
    $nuevo = [regex]::Replace($texto, '(?im)^\[mysqld\]\r?\n', ('[mysqld]' + $nl + 'innodb_use_native_aio=0' + $nl), 1)
    if ($nuevo -eq $texto) { Write-Aviso 'No se encontró la sección [mysqld] en my.ini; no se modificó.'; return }
    [System.IO.File]::WriteAllText($ini, $nuevo, (New-Object System.Text.UTF8Encoding($false)))
    Write-Ok 'innodb_use_native_aio=0 agregado a [mysqld] en C:\xampp\mysql\bin\my.ini.'
}

function Start-ApacheServicio {
    $conf = Join-Path $script:RaizXampp 'apache\conf\httpd.conf'
    $puertos = New-Object System.Collections.Generic.List[int]
    if (Test-Path -LiteralPath $conf) {
        Select-String -LiteralPath $conf -Pattern '^\s*Listen\s+(\S+)' | ForEach-Object {
            $numero = ($_.Matches[0].Groups[1].Value -split ':')[-1]
            if ($numero -match '^\d+$') { $puertos.Add([int]$numero) }
        }
    }
    if ($puertos.Count -eq 0) { $puertos.Add(80) }
    if (-not $puertos.Contains(443)) { $puertos.Add(443) }

    $bloqueado = $false
    foreach ($p in ($puertos | Select-Object -Unique)) {
        $pids = @(Get-EscuchaPuerto -Puerto $p)
        if ($pids.Count -gt 0) {
            $detalle = ($pids | ForEach-Object { '{0} (PID {1})' -f (Get-NombreProceso -IdProceso $_), $_ }) -join ', '
            Write-Aviso ('Puerto {0} ocupado por {1}. Apache no podrá iniciar mientras siga ocupado.' -f $p, $detalle)
            $bloqueado = $true
        }
        else { Write-Ok ('Puerto {0} libre.' -f $p) }
    }
    if ($bloqueado) { return 'PUERTO_OCUPADO' }

    Write-Info 'Iniciando Apache (httpd)...'
    $bin = Join-Path $script:RaizXampp 'apache\bin'
    $proceso = Start-Process -FilePath (Join-Path $bin 'httpd.exe') -WorkingDirectory $bin -WindowStyle Hidden -PassThru
    $puertoWeb = [int]$puertos[0]
    if (-not (Wait-Puerto -Puerto $puertoWeb -Segundos 20 -Proceso $proceso)) {
        Write-Aviso 'httpd.exe no quedó escuchando.'
        Show-UltimasLineas -Archivo (Join-Path $script:RaizXampp 'apache\logs\error.log')
        return 'FALLO'
    }
    try {
        $resp = Invoke-WebRequest -Uri ('http://localhost:{0}/' -f $puertoWeb) -UseBasicParsing -TimeoutSec 8
        Write-Ok ('Apache iniciado; responde HTTP {0} en el puerto {1}.' -f $resp.StatusCode, $puertoWeb)
    }
    catch {
        $codigo = $null
        if ($_.Exception.PSObject.Properties['Response'] -and $_.Exception.Response) { $codigo = [int]$_.Exception.Response.StatusCode }
        if ($codigo) { Write-Ok ('Apache iniciado; responde HTTP {0} en el puerto {1}.' -f $codigo, $puertoWeb) }
        else { Write-Aviso ('Apache escucha pero no respondió a la solicitud HTTP: {0}' -f $_.Exception.Message); return 'SIN_RESPUESTA' }
    }
    return 'OK'
}

function Test-AccesoMySql {
    # Equivale a 'mysql -u root -p -h localhost -P 3307 -D mysql' con contraseña vacía
    # (sin -p para no depender de una entrada interactiva).
    $bin = Join-Path $script:RaizXampp 'mysql\bin'
    $sql = 'SELECT CURRENT_USER() AS usuario, DATABASE() AS base_datos, VERSION() AS version; SHOW DATABASES;'
    $resultado = Invoke-Nativo -Exe (Join-Path $bin 'mysql.exe') -Argumentos @(
        '-u', 'root', '-h', 'localhost', '-P', "$($script:PuertoMySql)", '-D', 'mysql', '--connect-timeout=10', '-e', $sql)
    if ($resultado.Codigo -ne 0) {
        throw ('El cliente mysql devolvió el código {0}: {1}' -f $resultado.Codigo, $resultado.Salida)
    }
    Write-Ok 'Acceso a MySQL verificado (usuario root, sin contraseña, base de datos mysql).'
    $resultado.Salida -split "`r?`n" | ForEach-Object { Write-Host ('      ' + $_) -ForegroundColor DarkGray }
}

function Stop-MySqlLimpio {
    $bin = Join-Path $script:RaizXampp 'mysql\bin'
    $r = Invoke-Nativo -Exe (Join-Path $bin 'mysqladmin.exe') -Argumentos @(
        '-u', 'root', '-h', '127.0.0.1', '-P', "$($script:PuertoMySql)", 'shutdown')
    if ($r.Codigo -eq 0) { Write-Ok 'MySQL detenido de forma ordenada (mysqladmin shutdown).' }
    else { Write-Aviso ('No se pudo detener con mysqladmin: {0}' -f $r.Salida) }
}

function Stop-ServiciosVerificados {
    if ($script:MySqlIniciadoPorScript) { Stop-MySqlLimpio }
    Get-ProcesosXampp | Where-Object { $_.Name -eq 'httpd.exe' } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    Write-Ok 'Apache detenido.'
}

# ===========================================================================
# PROGRAMA PRINCIPAL
# ===========================================================================
$codigoSalida = 0
$dirLogs = $env:XAMPP_REPAIR_LOG_DIR
if ([string]::IsNullOrWhiteSpace($dirLogs)) { $dirLogs = Join-Path $env:LOCALAPPDATA 'xampp-repair-logs' }
$transcripcion = $false
try {
    New-Item -ItemType Directory -Path $dirLogs -Force | Out-Null
    Start-Transcript -Path (Join-Path $dirLogs ('repair-{0}.log' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))) | Out-Null
    $transcripcion = $true
}
catch { }

try {
    Write-Host '=== Reparación de XAMPP para Windows 11 (cuenta sin administrador) ===' -ForegroundColor White

    # --- 1. Contexto ---------------------------------------------------------
    Write-Paso '1' 'Contexto de la cuenta'
    Write-Info ('Usuario: {0}\{1}   PowerShell {2}' -f $env:USERDOMAIN, $env:USERNAME, $PSVersionTable.PSVersion)
    if (Test-EsAdministrador) { Write-Info 'La sesión actual está elevada (no es necesario).' }
    else { Write-Ok 'Sesión sin privilegios de administrador. No se requiere ni se solicita la contraseña de administrador.' }
    Add-Resumen '1' 'OK' 'Cuenta estándar; no se usa contraseña de administrador'

    # --- 2. Restricciones ----------------------------------------------------
    Write-Paso '2' 'Diagnóstico de restricciones de PowerShell y CMD'
    $hallazgos = Test-Restricciones
    if ($hallazgos -eq 0) { Add-Resumen '2' 'OK' 'Sin restricciones detectadas' }
    else { Add-Resumen '2' 'AVISO' ('{0} restricción(es) impuestas por directiva; ver detalle' -f $hallazgos) }

    # --- 3. Procesos y servicios ---------------------------------------------
    Write-Paso '3' 'Finalización de procesos y servicios de XAMPP'
    $activos = @(Get-ProcesosXampp)
    if ($activos.Count -eq 0) { Write-Ok 'No hay procesos de XAMPP en ejecución.' }
    else {
        Write-Info ('Procesos de XAMPP en ejecución: {0}' -f (($activos | ForEach-Object { $_.Name }) -join ', '))
        $restantes = @(Stop-ProcesosXampp)
        if ($restantes.Count -gt 0) { throw ('Persisten procesos de XAMPP que no se pudieron finalizar: {0}' -f (($restantes | ForEach-Object { $_.Name }) -join ', ')) }
    }
    $serviciosPendientes = Stop-ServiciosXampp
    if ($serviciosPendientes -gt 0) { Add-Resumen '3' 'AVISO' 'Hay servicios de Windows de XAMPP que exigen administrador para detenerse' }
    else { Add-Resumen '3' 'OK' 'Procesos y servicios de XAMPP detenidos' }

    # --- 4. Scripts ----------------------------------------------------------
    Write-Paso '4' 'Habilitación de ejecución de scripts'
    Enable-EjecucionScripts
    Add-Resumen '4' 'OK' 'RemoteSigned en CurrentUser; proyecto desbloqueado'

    # --- 5.1 / 5.2 -----------------------------------------------------------
    Write-Paso '5.1' 'Verificación de la instalación en C:\xampp'
    Test-InstalacionXampp
    Write-Ok 'Instalación completa y con permisos de escritura.'
    Add-Resumen '5.1' 'OK' 'C:\xampp verificado'

    Write-Paso '5.2' 'Verificación de instalaciones duplicadas'
    $duplicadas = @(Get-InstalacionesDuplicadas)
    if ($duplicadas.Count -gt 0) {
        $duplicadas | ForEach-Object { Write-Aviso ('Instalación adicional detectada: {0}' -f $_) }
        if (-not $AllowDuplicates) {
            throw 'Se detectaron instalaciones duplicadas de XAMPP. Retírelas (o use -AllowDuplicates bajo su responsabilidad) y vuelva a ejecutar.'
        }
        Add-Resumen '5.2' 'AVISO' ('Duplicadas ignoradas: {0}' -f ($duplicadas -join '; '))
    }
    else { Write-Ok 'No existen instalaciones duplicadas.'; Add-Resumen '5.2' 'OK' 'Sin duplicados' }

    # --- 5.3 a 5.5 -----------------------------------------------------------
    Write-Paso '5.3' 'Reemplazo de C:\xampp\mysql\data por data.zip'
    Restore-CarpetaData
    Add-Resumen '5.3' 'OK' 'Carpeta data reemplazada'

    Write-Paso '5.4' 'Reemplazo de C:\xampp\mysql\bin\my.ini'
    Set-ArchivoReemplazo -Origen (Join-Path $ResourcesPath 'my.ini') `
        -Destino (Join-Path $script:RaizXampp 'mysql\bin\my.ini') -Etiqueta 'my.ini'
    Add-Resumen '5.4' 'OK' 'my.ini reemplazado'

    Write-Paso '5.5' 'Reemplazo de C:\xampp\phpMyAdmin\config.inc.php'
    $origenConfig = Join-Path $ResourcesPath 'config.inc.php'
    if (-not (Test-Path -LiteralPath $origenConfig)) { $origenConfig = Join-Path $ResourcesPath 'config_inc.php' }
    Set-ArchivoReemplazo -Origen $origenConfig `
        -Destino (Join-Path $script:RaizXampp 'phpMyAdmin\config.inc.php') -Etiqueta 'config.inc.php'
    Add-Resumen '5.5' 'OK' 'config.inc.php reemplazado'

    # --- 5.6 -----------------------------------------------------------------
    Write-Paso '5.6' 'PATH del usuario: C:\xampp\mysql\bin'
    Add-RutaPathUsuario -Ruta (Join-Path $script:RaizXampp 'mysql\bin')
    Add-Resumen '5.6' 'OK' 'PATH de usuario actualizado (abrir una terminal nueva)'

    # --- 5.7 -----------------------------------------------------------------
    Write-Paso '5.7' 'Inicio de MySQL y Apache, y verificación de acceso a MySQL'
    Start-MySqlServicio
    if ($script:MySqlAio0) {
        if ($PersistNativeAio) { Set-NativeAioPersistente }
        else { Write-Aviso 'MySQL solo inicia con --innodb-use-native-aio=0. Para que también inicie desde el panel de XAMPP, repita con -PersistNativeAio.' }
        Add-Resumen '5.7a' 'AVISO' 'MySQL inició únicamente con --innodb-use-native-aio=0'
    }
    Add-Resumen '5.7a' 'OK' 'MySQL iniciado'

    if (-not $SkipApache) {
        $estadoApache = Start-ApacheServicio
        if ($estadoApache -eq 'OK') { Add-Resumen '5.7b' 'OK' 'Apache iniciado y respondiendo' }
        else { Add-Resumen '5.7b' 'AVISO' ('Apache: {0}' -f $estadoApache) }
    }

    Test-AccesoMySql
    Add-Resumen '5.7c' 'OK' 'mysql -u root -h localhost -P 3307 -D mysql operativo'

    if ($StopServices) {
        Stop-ServiciosVerificados
        Add-Resumen '5.7d' 'OK' 'Servicios detenidos (-StopServices)'
    }
}
catch {
    $codigoSalida = 1
    Write-Host ''
    Write-Host ('[ERROR] {0}' -f $_.Exception.Message) -ForegroundColor Red
    Add-Resumen 'ERROR' 'FALLO' $_.Exception.Message
}
finally {
    Write-Host ''
    Write-Host '=== Resumen ===' -ForegroundColor White
    ($script:Resumen | Format-Table -AutoSize -Wrap | Out-String).TrimEnd() | Write-Host
    if ($script:DirRespaldo) { Write-Host ('Respaldo de lo reemplazado: {0}' -f $script:DirRespaldo) }
    if ($codigoSalida -eq 0 -and ($NoShell -or $StopServices)) {
        Write-Host ''
        Write-Host 'Para la verificación manual abra una terminal NUEVA y ejecute:' -ForegroundColor White
        Write-Host '   mysql -u root -p -h localhost -P 3307 -D mysql' -ForegroundColor Green
        Write-Host '   (cuando solicite la contraseña, presione Enter: no tiene)' -ForegroundColor Gray
    }
    if ($transcripcion) { try { Stop-Transcript | Out-Null } catch { } }
}

if ($codigoSalida -eq 0 -and -not $NoShell -and -not $StopServices) {
    Write-Host ''
    Write-Host 'Abriendo el cliente con el comando indicado (MySQL y Apache siguen en ejecución):' -ForegroundColor White
    Write-Host '   mysql -u root -p -h localhost -P 3307 -D mysql' -ForegroundColor Green
    Write-Host '   Cuando solicite la contraseña, presione Enter (no tiene). Escriba exit para salir.' -ForegroundColor Gray
    & (Join-Path $script:RaizXampp 'mysql\bin\mysql.exe') -u root -p -h localhost -P $script:PuertoMySql -D mysql
}
exit $codigoSalida
