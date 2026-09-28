# Publicación en GitHub y GitLab (doble remoto)

Repositorios de destino:

- GitHub: `https://github.com/andres-gutierrezri/xampp-repair-windows11`
- GitLab: `https://gitlab.com/andres.gutierrezri/xampp-repair-windows11`

> Recomendación: cree ambos repositorios como **privados** mientras `static/data.zip` contenga datos de plantilla de MariaDB; hágalos públicos solo tras revisarlo.

## 1. Requisitos

```powershell
git --version
ssh -V
```

`ssh` (cliente OpenSSH) viene con Windows 11. Si `git` no existe, instale Git for Windows en modo **usuario actual** (el instalador no exige administrador cuando se elige esa opción).

## 2. Inicialización local

Ubíquese en la carpeta raíz del proyecto:

```powershell
cd C:\ruta\a\xampp-repair-windows11

# 2.1 Inicializar el repositorio con rama inicial main
git init -b main

# 2.2 Identidad (global para todos sus repositorios)
git config --global user.name  "Andrés Felipe Gutiérrez Rivera"
git config --global user.email "ID+andres-gutierrezri@users.noreply.github.com"   # correo privado de GitHub; sustituya ID

# 2.3 Fin de línea coherente con .gitattributes
git config --global core.autocrlf false

# 2.4 Revisar qué se versionará (no debe aparecer .env ni *.log)
git status

# 2.5 Preparar y confirmar (Conventional Commits)
git add .
git commit -m "feat: versión inicial de los scripts de reparación de XAMPP"
```

## 3. Crear los repositorios remotos (interfaz web)

**GitHub:** *New repository* → nombre `xampp-repair-windows11` → visibilidad Private → **no** marque *Add a README*, *.gitignore* ni *license* (el repositorio debe nacer vacío) → *Create repository*.

**GitLab:** *New project → Create blank project* → nombre `xampp-repair-windows11` → visibilidad Private → **desmarque** *Initialize repository with a README* → *Create project*.

## 4. Vincular y publicar (un remoto)

```powershell
git remote add origin https://github.com/andres-gutierrezri/xampp-repair-windows11.git
git branch -M main
git push -u origin main
```

## 5. Doble remoto

### Opción A — dos remotos con nombre (recomendada por transparencia)

```powershell
git remote add github https://github.com/andres-gutierrezri/xampp-repair-windows11.git
git remote add gitlab https://gitlab.com/andres.gutierrezri/xampp-repair-windows11.git
git remote -v

git push -u github main
git push -u gitlab main
```

Sincronización posterior con un único comando (alias):

```powershell
git config --global alias.pushall "!git push github --all && git push gitlab --all && git push github --tags && git push gitlab --tags"
git pushall
```

### Opción B — un solo remoto `origin` con dos URL de envío

Al agregar la primera URL de envío se reemplaza la implícita, por eso se agregan **ambas**:

```powershell
git remote set-url --add --push origin https://github.com/andres-gutierrezri/xampp-repair-windows11.git
git remote set-url --add --push origin https://gitlab.com/andres.gutierrezri/xampp-repair-windows11.git
git remote -v          # fetch: GitHub; push: GitHub y GitLab
git push -u origin main
```

## 6. Autenticación por SSH

```powershell
# 6.1 Generar el par de llaves (Ed25519); acepte la ruta por defecto y fije una frase de paso
ssh-keygen -t ed25519 -C "xampp-repair-windows11" -f "$env:USERPROFILE\.ssh\id_ed25519"

# 6.2 Mostrar la llave PÚBLICA (nunca comparta la privada)
Get-Content "$env:USERPROFILE\.ssh\id_ed25519.pub"
```

- GitHub: *Settings → SSH and GPG keys → New SSH key* → pegar la llave pública.
- GitLab: *Preferences → SSH Keys* → pegar la llave pública.

Como la cuenta **no es administradora**, el servicio `ssh-agent` (deshabilitado de forma predeterminada) no puede iniciarse. Solución: indicar la llave en `%USERPROFILE%\.ssh\config`:

```
Host github.com
    HostName github.com
    User git
    IdentityFile ~/.ssh/id_ed25519
    IdentitiesOnly yes

Host gitlab.com
    HostName gitlab.com
    User git
    IdentityFile ~/.ssh/id_ed25519
    IdentitiesOnly yes
```

```powershell
ssh -T git@github.com
ssh -T git@gitlab.com

# Cambiar los remotos de HTTPS a SSH
git remote set-url github git@github.com:andres-gutierrezri/xampp-repair-windows11.git
git remote set-url gitlab git@gitlab.com:andres.gutierrezri/xampp-repair-windows11.git
```

## 7. Autenticación por token de acceso personal (PAT)

- GitHub: *Settings → Developer settings → Personal access tokens → Fine-grained tokens* → repositorio `xampp-repair-windows11` → permiso **Contents: Read and write**.
- GitLab: *Preferences → Access tokens* → alcances `read_repository` y `write_repository`.

Use el asistente de credenciales (incluido en Git for Windows) para que el token se guarde cifrado, **no** dentro de la URL ni en el historial:

```powershell
git config --global credential.helper manager
git push -u github main     # solicita usuario y, como contraseña, el PAT
git push -u gitlab main
```

Si un token se expone, revóquelo de inmediato en el panel de la plataforma.

## 8. Ramificación con Git Flow

```powershell
git switch -c develop
git push -u github develop; git push -u gitlab develop

# Nueva funcionalidad
git switch -c feature/verificacion-apache develop
git commit -am "feat(apache): diagnostica puertos 80 y 443"
git switch develop
git merge --no-ff feature/verificacion-apache -m "merge: feature/verificacion-apache"
git branch -d feature/verificacion-apache

# Versión de lanzamiento
git switch -c release/1.1.0 develop
git commit -am "chore(release): prepara 1.1.0"
git switch main
git merge --no-ff release/1.1.0 -m "release: 1.1.0"
git tag -a v1.1.0 -m "Versión 1.1.0"
git switch develop
git merge --no-ff release/1.1.0
git branch -d release/1.1.0

# Corrección urgente
git switch -c hotfix/1.1.1 main
```

## 9. Mensajes de commit (Conventional Commits 1.0.0)

Formato: `tipo(ámbito opcional): descripción`

```
feat(ps1): agrega verificación de duplicados
fix(bat): corrige lectura de PATH con paréntesis
docs: actualiza guía de publicación
test: valida CRLF en archivos .bat
chore(ci): añade PSScriptAnalyzer
feat!: cambia el nombre del parámetro -NoBackup
```

## 10. Versionado semántico (SemVer 2.0.0)

`MAYOR.MENOR.PARCHE`: MAYOR si rompe compatibilidad, MENOR si agrega funciones compatibles, PARCHE si corrige errores.

```powershell
git tag -a v1.0.0 -m "Primera versión estable"
git push github v1.0.0
git push gitlab v1.0.0
# o todas las etiquetas
git push github --tags; git push gitlab --tags
```

## 11. Verificación final

```powershell
git remote -v
git log --oneline --graph --decorate --all
git status
```
