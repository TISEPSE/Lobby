@echo off
title Lobby
rem Le dossier de ce fichier : le projet peut etre renomme ou deplace.
cd /d "%~dp0"
echo Demarrage de Lobby...

rem Rust installe : lancement normal, avec recompilation.
where cargo >nul 2>nul
if not errorlevel 1 (
    call npm run tauri dev
    if not errorlevel 1 exit /b 0
    echo La compilation a echoue : lancement de la derniere version compilee.
)

rem Sans Rust, ou si la compilation echoue (Smart App Control bloque les
rem scripts de compilation), on reprend l'executable deja compile : il charge
rem l'interface depuis Vite, donc les changements du front sont bien la.
if not exist "src-tauri\target\debug\app.exe" (
    echo Aucun executable compile n'a ete trouve.
    echo Il faut Rust, sur https://rustup.rs, et une compilation qui aboutit.
    goto failed
)

tasklist /fi "imagename eq app.exe" | find /i "app.exe" >nul
if not errorlevel 1 (
    echo Lobby est deja ouvert.
    exit /b 0
)

rem Vite n'est lance ici que s'il ne tourne pas deja.
set "STARTED_VITE="
curl -s -o nul --max-time 1 http://localhost:5177/
if not errorlevel 1 goto launch

set "STARTED_VITE=1"
start "Lobby - Vite" /min cmd /c npm run dev -- --port 5177 --strictPort
set /a TRIES=0

:wait_vite
curl -s -o nul --max-time 1 http://localhost:5177/
if not errorlevel 1 goto launch
set /a TRIES+=1
if %TRIES% geq 30 (
    echo Vite n'a pas demarre sur le port 5177.
    goto failed
)
timeout /t 1 /nobreak >nul
goto wait_vite

:launch
start "" /wait "src-tauri\target\debug\app.exe"

rem Lobby ferme : on arrete le Vite demarre par ce fichier, et lui seul.
if defined STARTED_VITE (
    powershell -NoProfile -Command "Get-NetTCPConnection -LocalPort 5177 -State Listen -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.OwningProcess -Force }"
)
exit /b 0

:failed
echo Une erreur est survenue lors du lancement de l'application.
pause
exit /b 1
