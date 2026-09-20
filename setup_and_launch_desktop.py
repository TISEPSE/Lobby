import os
import subprocess

desktop_dir = r"C:\Users\User\Desktop"
project_dir = r"D:\Dev\Interface-console"
icon_path = os.path.join(project_dir, "src-tauri", "icons", "icon.ico")
batch_file = os.path.join(project_dir, "launch_console.bat")
desktop_batch = os.path.join(desktop_dir, "Interface Console.bat")
shortcut_path = os.path.join(desktop_dir, "Interface Console.lnk")

# 1. Create launch_console.bat
batch_content = f"""@echo off
title Interface Console
cd /d "{project_dir}"
echo Demarrage de l'Interface Console...
npm run tauri dev
"""
with open(batch_file, "w", encoding="utf-8") as f:
    f.write(batch_content)

with open(desktop_batch, "w", encoding="utf-8") as f:
    f.write(batch_content)

# 2. Create shortcut .lnk on Desktop pointing to launch_console.bat with icon
ps_script = f"""
$WshShell = New-Object -ComObject WScript.Shell
$Shortcut = $WshShell.CreateShortcut('{shortcut_path}')
$Shortcut.TargetPath = '{batch_file}'
$Shortcut.WorkingDirectory = '{project_dir}'
$Shortcut.Description = 'Interface Console'
if (Test-Path '{icon_path}') {{
    $Shortcut.IconLocation = '{icon_path},0'
}}
$Shortcut.Save()
"""
with open("create_lnk.ps1", "w", encoding="utf-8") as f:
    f.write(ps_script)

subprocess.run(["powershell", "-ExecutionPolicy", "Bypass", "-File", "create_lnk.ps1"], check=True)

# 3. Launch the app on the desktop using os.startfile (which acts as a user double-click in Windows)
os.startfile(desktop_batch)

print("Desktop launcher created and executed on interactive user desktop!")
