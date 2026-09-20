import os
import subprocess

# 1. Create Desktop shortcut using Windows Script Host
desktop_dir = os.path.expanduser(r"C:\Users\User\Desktop")
shortcut_path = os.path.join(desktop_dir, "Interface Console.lnk")
target_exe = r"D:\Dev\Interface-console\src-tauri\target\debug\app.exe"
work_dir = r"D:\Dev\Interface-console"
icon_path = r"D:\Dev\Interface-console\src-tauri\icons\icon.ico"

ps_script = f'''
$WshShell = New-Object -ComObject WScript.Shell
$Shortcut = $WshShell.CreateShortcut('{shortcut_path}')
$Shortcut.TargetPath = '{target_exe}'
$Shortcut.WorkingDirectory = '{work_dir}'
if (Test-Path '{icon_path}') {{
    $Shortcut.IconLocation = '{icon_path}'
}}
$Shortcut.Save()

# Launch via Shell.Application so it attaches directly to interactive user desktop session
$shell = New-Object -ComObject Shell.Application
$shell.ShellExecute('{target_exe}', '', '{work_dir}', 'open', 1)
'''

with open("scratch_launch.ps1", "w", encoding="utf-8") as f:
    f.write(ps_script)

res = subprocess.run(["powershell", "-ExecutionPolicy", "Bypass", "-File", "scratch_launch.ps1"], capture_output=True, text=True)
print("STDOUT:", res.stdout)
print("STDERR:", res.stderr)
print("Returncode:", res.returncode)
if os.path.exists(shortcut_path):
    print(f"Shortcut created successfully at {shortcut_path}")
