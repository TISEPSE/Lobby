
$WshShell = New-Object -ComObject WScript.Shell
$Shortcut = $WshShell.CreateShortcut('C:\Users\User\Desktop\Interface Console.lnk')
$Shortcut.TargetPath = 'D:\Dev\Interface-console\launch_console.bat'
$Shortcut.WorkingDirectory = 'D:\Dev\Interface-console'
$Shortcut.Description = 'Interface Console'
if (Test-Path 'D:\Dev\Interface-console\src-tauri\icons\icon.ico') {
    $Shortcut.IconLocation = 'D:\Dev\Interface-console\src-tauri\icons\icon.ico,0'
}
$Shortcut.Save()
