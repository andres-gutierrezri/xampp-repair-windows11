# Changelog

Formato basado en [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/) y versionado [SemVer](https://semver.org/lang/es/).

## [1.1.0] - 2026-09-28
### Cambiado
- Fase 5.7: primero se inician MySQL y Apache (ambos quedan en ejecución) y después se verifica el acceso; al final se abre `mysql -u root -p -h localhost -P 3307 -D mysql`.
- `-StopMySql` se reemplaza por `-StopServices` (detiene MySQL y Apache).
### Añadido
- `-NoNativeAio` / `/NOAIO`, `-PersistNativeAio` / `/PERSISTAIO` y `-NoShell` / `/NOSHELL`.
- Reintento automático (PowerShell) con `--innodb-use-native-aio=0` si `mysqld` falla al iniciar (`InnoDB: Failing assertion: slot`).
### Corregido
- `$PSScriptRoot` vacío en el bloque `param` y `Count` sobre `$null` con `StrictMode` en Windows PowerShell 5.1.

## [1.0.0] - 2026-09-28
### Añadido
- `src/Repair-Xampp.ps1`: reparación completa (fases 1 a 5.7) en PowerShell, sin administrador.
- `src/repair-xampp.bat`: versión equivalente en CMD.
- `src/run-powershell-repair.bat`: lanzador con `-ExecutionPolicy Bypass` solo para el proceso hijo.
- `static/`: `data.zip`, `my.ini` y `config.inc.php` (puerto 3307).
- `tests/Test-Project.ps1`: pruebas estáticas de sintaxis, codificación y recursos.
- Documentación de publicación en GitHub y GitLab (doble remoto).
