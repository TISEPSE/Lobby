
$WshShell = New-Object -ComObject WScript.Shell
$Shortcut = $WshShell.CreateShortcut('C:\Users\User\Desktop\Interface Console.lnk')
$Shortcut.TargetPath = 'D:\Dev\Interface-console\src-tauri\target\debug\app.exe'
$Shortcut.WorkingDirectory = 'D:\Dev\Interface-console'
if (Test-Path 'D:\Dev\Interface-console\src-tauri\icons\icon.ico') {
    $Shortcut.IconLocation = 'D:\Dev\Interface-console\src-tauri\icons\icon.ico'
}
$Shortcut.Save()

# Launch via Shell.Application so it attaches directly to interactive user desktop session
$shell = New-Object -ComObject Shell.Application
$shell.ShellExecute('D:\Dev\Interface-console\src-tauri\target\debug\app.exe', '', 'D:\Dev\Interface-console', 'open', 1)
