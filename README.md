# xampp-repair-windows11

Scripts en **PowerShell** y **CMD (Batch)** para reparar XAMPP cuando **Apache** y **MySQL/MariaDB** no inician, en **Windows 11**, desde una **cuenta local sin privilegios de administrador** (con la contraseña de administrador desconocida).

![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-5391FE?logo=powershell&logoColor=white)
![CMD](https://img.shields.io/badge/CMD-Batch-4D4D4D?logo=windowsterminal&logoColor=white)
![Windows 11](https://img.shields.io/badge/Windows-11-0078D4?logo=windows11&logoColor=white)
![Versión](https://img.shields.io/badge/versi%C3%B3n-1.0.0-2ea44f)
![Licencia](https://img.shields.io/badge/licencia-MIT-blue)

## Tabla de contenidos

1. [Qué hace el proyecto](#qué-hace-el-proyecto)
2. [Requisitos previos](#requisitos-previos)
3. [Instalación paso a paso](#instalación-paso-a-paso)
4. [Entorno virtual](#entorno-virtual-venv--virtualenv)
5. [Instalación de dependencias](#instalación-de-dependencias)
6. [Configuración de variables de entorno](#configuración-de-variables-de-entorno)
7. [Migraciones y datos iniciales](#migraciones-y-carga-de-datos-iniciales)
8. [Ejecución](#ejecución)
9. [Pruebas](#pruebas)
10. [Estructura del proyecto](#estructura-del-proyecto)
11. [Límites y advertencias de seguridad](#límites-y-advertencias-de-seguridad)
12. [Publicación en GitHub y GitLab](#publicación-en-github-y-gitlab)
13. [Autor](#autor)
14. [Licencia](#licencia)

## Qué hace el proyecto

| Fase | Acción |
|---|---|
| 1 | Confirma que la sesión es estándar; **no solicita, almacena ni intenta eludir** la contraseña de administrador. |
| 2 | Diagnostica restricciones de PowerShell y CMD (directivas de grupo, `DisableCMD`, modo de lenguaje). |
| 3 | Finaliza procesos y servicios de XAMPP, **solo** los ejecutados desde `C:\xampp`. |
| 4 | Habilita scripts: `RemoteSigned` en el ámbito `CurrentUser` y `Unblock-File` sobre el proyecto. |
| 5.1 | Verifica que XAMPP esté en `C:\xampp` y que la cuenta pueda escribir allí. |
| 5.2 | Verifica que no existan instalaciones duplicadas. |
| 5.3 | Reemplaza `C:\xampp\mysql\data` con `static\data.zip`. |
| 5.4 | Reemplaza `C:\xampp\mysql\bin\my.ini`. |
| 5.5 | Reemplaza `C:\xampp\phpMyAdmin\config.inc.php`. |
| 5.6 | Agrega `C:\xampp\mysql\bin` al `PATH` **del usuario** (ver [docs/img](docs/img)). |
| 5.7 | Inicia MySQL y verifica `mysql -u root -h localhost -P 3307 -D mysql` sin contraseña. |
| + | Diagnóstico complementario de Apache (puertos y respuesta HTTP), sin modificar archivos. |

Lo reemplazado **no se destruye**: se traslada a `%LOCALAPPDATA%\xampp-repair-backup\<fecha>` (fuera de `C:\xampp`). Use `-NoBackup` (PowerShell) o `/NOBACKUP` (CMD) para eliminarlo definitivamente.

## Requisitos previos

- Windows 11 con una cuenta local estándar.
- XAMPP instalado en **`C:\xampp`** (sin copias adicionales).
- Windows PowerShell 5.1 (incluido) o PowerShell 7+.
- `tar.exe` y `robocopy.exe` (incluidos en Windows 10/11) para la versión CMD.
- Permiso de modificación de la cuenta sobre `C:\xampp\mysql`, `C:\xampp\mysql\bin` y `C:\xampp\phpMyAdmin` (el script lo comprueba).
- Git (opcional, solo para clonar y publicar).

## Instalación paso a paso

1. Clone el repositorio (o descargue el `.zip` y descomprímalo):

   ```powershell
   git clone https://github.com/andres-gutierrezri/xampp-repair-windows11.git
   cd xampp-repair-windows11
   ```

2. Si descargó un `.zip`, no es necesario desbloquearlo manualmente: los lanzadores ejecutan `Unblock-File` sobre el proyecto.

## Entorno virtual (`venv` / `virtualenv`)

**No aplica.** El proyecto no usa Python; por tanto no se crea ni se activa ningún entorno virtual. Si en el futuro se añaden utilidades en Python, el procedimiento sería:

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
```

## Instalación de dependencias

**No aplica** (`pip install -r requirements.txt` no instala nada: el archivo solo documenta los requisitos del sistema). Herramienta opcional de desarrollo:

```powershell
Install-Module PSScriptAnalyzer -Scope CurrentUser
```

## Configuración de variables de entorno

Las variables son **opcionales** (ver [`.env.example`](.env.example)):

| Variable | Efecto | Valor por defecto |
|---|---|---|
| `XAMPP_REPAIR_BACKUP_DIR` | Carpeta base de respaldos | `%LOCALAPPDATA%\xampp-repair-backup` |
| `XAMPP_REPAIR_LOG_DIR` | Carpeta de bitácoras (PowerShell) | `%LOCALAPPDATA%\xampp-repair-logs` |

Ejemplo para la sesión actual:

```powershell
$env:XAMPP_REPAIR_BACKUP_DIR = "D:\respaldos-xampp"
```

## Migraciones y carga de datos iniciales

No hay migraciones. La “carga inicial” es el contenido de `static\data.zip`, que se instala en `C:\xampp\mysql\data` (fase 5.3). Debe corresponder a la **misma línea de versión de MariaDB** que trae su XAMPP; ver [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md).

## Ejecución

Versión PowerShell (recomendada; el lanzador aplica `-ExecutionPolicy Bypass` solo al proceso hijo):

```cmd
src\run-powershell-repair.bat
```

Directamente desde PowerShell:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\src\Repair-Xampp.ps1
```

Versión CMD:

```cmd
src\repair-xampp.bat
```

Opciones:

| PowerShell | CMD | Efecto |
|---|---|---|
| `-NoBackup` | `/NOBACKUP` | No conserva respaldo de lo reemplazado |
| `-AllowDuplicates` | `/ALLOWDUP` | Continúa aunque existan otras instalaciones de XAMPP |
| `-SkipApache` | `/SKIPAPACHE` | Omite la prueba de Apache |
| `-StopMySql` | `/STOPMYSQL` | Detiene MySQL al finalizar |
| `-NoNativeAio` | — | Diagnóstico: inicia `mysqld` con `--innodb-use-native-aio=0` sin tocar `my.ini` |

Verificación manual final (**en una terminal nueva**, para que lea el `PATH` actualizado). Al pedir la contraseña, presione **Enter**:

```cmd
mysql -u root -p -h localhost -P 3307 -D mysql
```

## Pruebas

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-Project.ps1
```

Valida sintaxis, codificación (BOM/CRLF), integridad de `data.zip` y coherencia del puerto `3307`. Las pruebas **no** modifican XAMPP.

## Estructura del proyecto

```
xampp-repair-windows11/
├── src/
│   ├── Repair-Xampp.ps1            # Implementación principal (PowerShell)
│   ├── repair-xampp.bat            # Implementación equivalente (CMD)
│   └── run-powershell-repair.bat   # Lanzador con Bypass solo para el proceso hijo
├── static/                         # Recursos que se instalan en C:\xampp
│   ├── data.zip                    # Directorio de datos de MariaDB (raíz interna: data/)
│   ├── my.ini                      # Configuración del servidor (puerto 3307)
│   └── config.inc.php              # Configuración de phpMyAdmin (127.0.0.1:3307)
├── tests/Test-Project.ps1          # Pruebas estáticas
├── docs/
│   ├── PUBLICACION_GITHUB_GITLAB.md
│   ├── TROUBLESHOOTING.md
│   └── img/                        # Capturas del procedimiento de PATH
├── .github/workflows/ci.yml        # Integración continua (PSScriptAnalyzer + pruebas)
├── PSScriptAnalyzerSettings.psd1
├── requirements.txt  .env.example  .gitignore  .gitattributes
├── CHANGELOG.md  LICENSE  README.md
```

`templates/` no se incluye porque el proyecto no genera HTML.

## Límites y advertencias de seguridad

- **No se eluden controles administrativos.** Si una directiva de grupo (GPO), AppLocker o `DisableCMD` impide algo, el script lo informa y no intenta sortearlo. Detener *servicios de Windows* también exige administrador.
- El `my.ini` provisto **no fija `bind-address`** y `root` **no tiene contraseña**: en ese caso MariaDB puede aceptar conexiones desde la red local. Use el equipo solo en redes de confianza o agregue `bind-address="127.0.0.1"` en `[mysqld]`.
- `static/data.zip` contiene las bases `mysql`, `performance_schema`, `phpmyadmin` y `test`. Si en el futuro incorpora datos reales, **no lo publique** en un repositorio público.

## Publicación en GitHub y GitLab

Procedimiento detallado, comando por comando (Git, doble remoto, SSH, PAT, Git Flow, Conventional Commits y SemVer): [docs/PUBLICACION_GITHUB_GITLAB.md](docs/PUBLICACION_GITHUB_GITLAB.md).

## Autor

**Ingeniero Andrés Felipe Gutiérrez Rivera**

- GitHub: <https://github.com/andres-gutierrezri>
- GitLab: <https://gitlab.com/andres.gutierrezri>
- LinkedIn: <https://www.linkedin.com/in/felipe-gutierrezri>

## Licencia

Distribuido bajo licencia **MIT**. Consulte [LICENSE](LICENSE).
