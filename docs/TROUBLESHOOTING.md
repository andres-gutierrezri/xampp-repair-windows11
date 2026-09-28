# Solución de problemas

| Síntoma | Causa probable | Acción |
|---|---|---|
| `Esta cuenta no tiene permiso de escritura en C:\xampp\...` | Las ACL de la carpeta no otorgan *Modificar* a su cuenta. | Sin administrador no hay vía legítima. Solicite a quien administre el equipo que otorgue *Modificar* sobre `C:\xampp` a su usuario. |
| `Una directiva de grupo (GPO) define la política...` | `MachinePolicy`/`UserPolicy` imponen la política de ejecución. | No puede cambiarse sin administrador. Use el `.bat` (no depende de la política de ejecución de PowerShell). |
| `DisableCMD = 1` | Directiva que bloquea `cmd.exe` y `.bat`. | Use la versión PowerShell; si ambas están bloqueadas, se requiere el administrador del equipo. |
| `El puerto 3307 ya está en uso` | Otra instancia de MariaDB/MySQL. | Identifique el PID con `Get-NetTCPConnection -LocalPort 3307` y finalice ese proceso si es suyo. |
| Apache no inicia: puerto 80/443 ocupado (PID 4, `System`) | `http.sys`/IIS u otro servicio de Windows. | Detener servicios exige administrador. Alternativa: cambiar `Listen` en `httpd.conf` (queda fuera del alcance de las fases 5.3 a 5.5). |
| `mysqld` inicia y se cierra; error de InnoDB/Aria en `mysql_error.log` | `data.zip` proviene de otra versión de MariaDB que la de su XAMPP. | Use un `data.zip` generado con la misma línea de versión de MariaDB de su XAMPP, o ejecute la actualización de tablas del sistema de su versión. |
| `mysql` no se reconoce | La terminal se abrió antes del cambio de `PATH`. | Cierre y abra una terminal nueva. |
| Se ejecuta otro `mysql.exe` | Otra instalación de MySQL/MariaDB antecede en el `PATH` (el `PATH` del sistema precede al del usuario). | Ejecute `where mysql` y use la ruta completa `C:\xampp\mysql\bin\mysql.exe`. |
| Aviso del Firewall de Windows al iniciar `mysqld`/`httpd` | Solicitud de regla de entrada. | Requiere administrador; para uso local (`127.0.0.1`) puede cancelarse. |
| El panel de XAMPP muestra otro puerto para MySQL | El panel conserva su propio ajuste de puertos. | Revise *Config → Service and Port Settings* y confirme que MySQL use 3307 (comportamiento no verificado en todas las versiones). |

## Ubicación de bitácoras

- Transcripción del script PowerShell: `%LOCALAPPDATA%\xampp-repair-logs\`
- MariaDB: `C:\xampp\mysql\data\mysql_error.log`
- Apache: `C:\xampp\apache\logs\error.log`
