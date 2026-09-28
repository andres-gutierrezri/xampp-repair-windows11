# Changelog

Formato basado en [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/) y versionado [SemVer](https://semver.org/lang/es/).

## [1.0.0] - 2026-09-28
### Añadido
- `src/Repair-Xampp.ps1`: reparación completa (fases 1 a 5.7) en PowerShell, sin administrador.
- `src/repair-xampp.bat`: versión equivalente en CMD.
- `src/run-powershell-repair.bat`: lanzador con `-ExecutionPolicy Bypass` solo para el proceso hijo.
- `static/`: `data.zip`, `my.ini` y `config.inc.php` (puerto 3307).
- `tests/Test-Project.ps1`: pruebas estáticas de sintaxis, codificación y recursos.
- Documentación de publicación en GitHub y GitLab (doble remoto).
