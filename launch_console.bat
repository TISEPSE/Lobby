@echo off
title Interface Console
cd /d "D:\Dev\Interface-console"
echo Demarrage de l'Interface Console...
call npm run tauri dev
if %errorlevel% neq 0 (
    echo Une erreur est survenue lors du lancement de l'application.
    pause
)
