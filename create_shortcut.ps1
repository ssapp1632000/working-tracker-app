Remove-Item "C:\Users\Ahmed Shaban\Desktop\Silver Stone.lnk" -Force -ErrorAction SilentlyContinue
$ws = New-Object -ComObject WScript.Shell
$shortcut = $ws.CreateShortcut("C:\Users\Ahmed Shaban\Desktop\Silver Stone.lnk")
$shortcut.TargetPath = "d:\silverstone-work\working-tracker-app\build\windows\x64\runner\Release\silver_stone.exe"
$shortcut.IconLocation = "d:\silverstone-work\working-tracker-app\build\windows\x64\runner\Release\silver_stone.exe,0"
$shortcut.Save()
Write-Host "New shortcut created"
