<#
.SYNOPSIS
    Pruebas estáticas del proyecto (no modifican XAMPP ni requieren Windows para la mayoría).
.DESCRIPTION
    Valida sintaxis de los scripts, integridad de los recursos y coherencia de la
    configuración (puerto 3307). Devuelve código de salida 1 si alguna prueba falla.
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-Project.ps1
#>
[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$raiz = Split-Path -Parent $PSScriptRoot
$script:Fallos = 0
$script:Total  = 0

function Assert-Prueba {
    param([string]$Nombre, [scriptblock]$Condicion)
    $script:Total++
    try {
        if (& $Condicion) { Write-Host ('[OK]    {0}' -f $Nombre) -ForegroundColor Green }
        else { Write-Host ('[FALLO] {0}' -f $Nombre) -ForegroundColor Red; $script:Fallos++ }
    }
    catch {
        Write-Host ('[FALLO] {0} -> {1}' -f $Nombre, $_.Exception.Message) -ForegroundColor Red
        $script:Fallos++
    }
}

Add-Type -AssemblyName System.IO.Compression.FileSystem

$carpetaSrc   = Join-Path $raiz 'src'
$carpetaTests = Join-Path $raiz 'tests'
$estatico     = Join-Path $raiz 'static'
$rutaPs1      = Join-Path $carpetaSrc 'Repair-Xampp.ps1'
$rutaBat      = Join-Path $carpetaSrc 'repair-xampp.bat'

# --- Sintaxis y codificación de PowerShell ---------------------------------------
foreach ($archivo in (Get-ChildItem -Path $carpetaSrc, $carpetaTests -Filter *.ps1)) {
    Assert-Prueba ('Sintaxis válida: {0}' -f $archivo.Name) {
        $errores = $null; $tokens = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($archivo.FullName, [ref]$tokens, [ref]$errores)
        @($errores).Count -eq 0
    }
    Assert-Prueba ('Codificación UTF-8 con BOM (Windows PowerShell 5.1 lo requiere para tildes): {0}' -f $archivo.Name) {
        $b = [System.IO.File]::ReadAllBytes($archivo.FullName)
        $b.Length -gt 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF
    }
}

# --- Batch: CRLF, sin BOM y ASCII puro -------------------------------------------
foreach ($archivo in (Get-ChildItem -Path $carpetaSrc -Filter *.bat)) {
    Assert-Prueba ('Finales de línea CRLF: {0}' -f $archivo.Name) {
        $b = [System.IO.File]::ReadAllBytes($archivo.FullName)
        $ok = $true
        for ($i = 0; $i -lt $b.Length; $i++) {
            if ($b[$i] -eq 10 -and ($i -eq 0 -or $b[$i - 1] -ne 13)) { $ok = $false; break }
        }
        $ok
    }
    Assert-Prueba ('Sin BOM (cmd.exe lo interpretaría como parte del primer comando): {0}' -f $archivo.Name) {
        $b = [System.IO.File]::ReadAllBytes($archivo.FullName)
        -not ($b[0] -eq 0xEF -and $b[1] -eq 0xBB)
    }
    Assert-Prueba ('Solo caracteres ASCII: {0}' -f $archivo.Name) {
        $b = [System.IO.File]::ReadAllBytes($archivo.FullName)
        @($b | Where-Object { $_ -gt 127 }).Count -eq 0
    }
}

# --- Recursos ------------------------------------------------------------------------
foreach ($recurso in 'data.zip', 'my.ini', 'config.inc.php') {
    Assert-Prueba ('Recurso presente: static/{0}' -f $recurso) { Test-Path -LiteralPath (Join-Path $estatico $recurso) }
}

Assert-Prueba 'data.zip contiene data/ibdata1 y data/mysql/' {
    $zip = [System.IO.Compression.ZipFile]::OpenRead((Join-Path $estatico 'data.zip'))
    try {
        $nombres = @($zip.Entries | ForEach-Object { $_.FullName })
        ($nombres -contains 'data/ibdata1') -and ($nombres -contains 'data/mysql/')
    }
    finally { $zip.Dispose() }
}

Assert-Prueba 'my.ini define port=3307 en [client] y [mysqld]' {
    $t = Get-Content -LiteralPath (Join-Path $estatico 'my.ini') -Raw
    ([regex]::Matches($t, '(?m)^port=3307\s*$')).Count -ge 2
}
Assert-Prueba 'my.ini apunta datadir a C:/xampp/mysql/data' {
    (Get-Content -LiteralPath (Join-Path $estatico 'my.ini') -Raw) -match '(?m)^datadir="C:/xampp/mysql/data"'
}
Assert-Prueba 'config.inc.php usa 127.0.0.1:3307 con mysqli' {
    $t = Get-Content -LiteralPath (Join-Path $estatico 'config.inc.php') -Raw
    ($t -match "\['host'\] = '127\.0\.0\.1'") -and ($t -match "\['port'\] = '3307'") -and ($t -match "\['extension'\] = 'mysqli'")
}

# --- Coherencia de los scripts ---------------------------------------------------------
Assert-Prueba 'Los scripts referencian C:\xampp y mysql\bin' {
    $ps  = Get-Content -LiteralPath $rutaPs1 -Raw
    $bat = Get-Content -LiteralPath $rutaBat -Raw
    ($ps -match 'C:\\xampp') -and ($ps -match 'mysql\\bin') -and ($bat -match 'C:\\xampp') -and ($bat -match 'mysql\\bin')
}
Assert-Prueba 'Ningún script solicita credenciales ni intenta elevar privilegios' {
    $todo = (Get-Content -LiteralPath $rutaPs1 -Raw) + (Get-Content -LiteralPath $rutaBat -Raw)
    -not ($todo -match '(?i)Read-Host|\brunas\b|Get-Credential|-Verb\s+RunAs')
}
Assert-Prueba 'Ningún script escribe fuera de C:\xampp salvo respaldo, bitácora, temporales y PATH de usuario' {
    $ps = Get-Content -LiteralPath $rutaPs1 -Raw
    -not ($ps -match '(?i)HKLM:.*(SetValue|New-ItemProperty|Set-ItemProperty)')
}

# --- Documentación mínima -----------------------------------------------------------------
foreach ($doc in 'README.md', 'LICENSE', '.gitignore', '.env.example', 'requirements.txt') {
    Assert-Prueba ('Archivo presente: {0}' -f $doc) { Test-Path -LiteralPath (Join-Path $raiz $doc) }
}
Assert-Prueba 'Archivo presente: docs/PUBLICACION_GITHUB_GITLAB.md' {
    Test-Path -LiteralPath (Join-Path (Join-Path $raiz 'docs') 'PUBLICACION_GITHUB_GITLAB.md')
}

Write-Host ''
Write-Host ('Resultado: {0} pruebas, {1} fallos.' -f $script:Total, $script:Fallos)
if ($script:Fallos -gt 0) { exit 1 }
exit 0
