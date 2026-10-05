<#
  Инвентаризация Windows перед переездом на Arch (ArchTry).
  Ничего не удаляет и не меняет: только читает и копирует в папку на рабочем столе.

  Запуск (PowerShell от администратора — нужно для паролей Wi-Fi):
    powershell -ExecutionPolicy Bypass -File .\inventory.ps1

  Результат: Desktop\ArchTry-inventory-<дата>\
    public\   — список программ, размеры папок. Можно присылать Claude (архив public.zip).
    secrets\  — конфиги VPN, SSH-ключи, Tabby, Wi-Fi. НИКУДА не отправлять и не класть в git!
                Перенести на внешний диск, лучше в архив с паролем (7-Zip, AES-256).
#>

param(
    [string]$OutRoot = [Environment]::GetFolderPath('Desktop'),
    [switch]$SkipSizes   # пропустить подсчёт размеров папок (самая долгая часть)
)

$ErrorActionPreference = 'Continue'
$stamp = Get-Date -Format 'yyyy-MM-dd_HHmm'
$Out = Join-Path $OutRoot "ArchTry-inventory-$stamp"
$Pub = Join-Path $Out 'public'
$Sec = Join-Path $Out 'secrets'
New-Item -ItemType Directory -Force -Path $Pub, $Sec | Out-Null

$notes = New-Object System.Collections.Generic.List[string]   # что сделать руками
$saved = New-Object System.Collections.Generic.List[string]   # что сохранено в secrets

function Log([string]$m) { Write-Host "[*] $m" -ForegroundColor Cyan }
function Note([string]$m) { Write-Host "[!] $m" -ForegroundColor Yellow; $notes.Add($m) }

function Save-Secret([string]$Src, [string]$Name) {
    if (-not (Test-Path -LiteralPath $Src)) { return }
    $dst = Join-Path $Sec $Name
    New-Item -ItemType Directory -Force -Path (Split-Path $dst) | Out-Null
    Copy-Item -LiteralPath $Src -Destination $dst -Recurse -Force -ErrorAction SilentlyContinue
    $saved.Add("$Name  <-  $Src")
    Log "saved: $Name"
}

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).
    IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { Note 'Скрипт запущен без прав администратора: пароли Wi-Fi не будут сохранены открытым текстом.' }

# ---------------------------------------------------------------- 1. Программы
Log 'Installed programs (registry)'
$uninstallKeys = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
                 'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
                 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
$programs = Get-ItemProperty $uninstallKeys -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName -and -not $_.SystemComponent -and -not $_.ParentKeyName } |
    Select-Object DisplayName, DisplayVersion, Publisher, InstallDate, InstallLocation,
        @{ n = 'SizeMB'; e = { if ($_.EstimatedSize) { [math]::Round($_.EstimatedSize / 1024) } } } |
    Sort-Object DisplayName -Unique
$programs | Export-Csv (Join-Path $Pub 'programs.csv') -NoTypeInformation -Encoding UTF8

Log 'Microsoft Store apps'
Get-AppxPackage -ErrorAction SilentlyContinue |
    Where-Object { $_.SignatureKind -eq 'Store' -and -not $_.IsFramework } |
    Select-Object Name, Version, Publisher |
    Export-Csv (Join-Path $Pub 'store-apps.csv') -NoTypeInformation -Encoding UTF8

# winget export: после переустановки Windows `winget import -i winget.json` поставит всё обратно
if (Get-Command winget -ErrorAction SilentlyContinue) {
    Log 'winget export'
    winget export -o (Join-Path $Pub 'winget.json') --include-versions --accept-source-agreements | Out-Null
}

# Ярлыки: так находятся портативные программы (Throne и т.п.), которых нет в реестре
Log 'Shortcuts (Start menu + Desktop)'
$wsh = New-Object -ComObject WScript.Shell
$lnkDirs = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs",
           "$env:ProgramData\Microsoft\Windows\Start Menu\Programs",
           [Environment]::GetFolderPath('Desktop'),
           "$env:PUBLIC\Desktop"
$shortcuts = Get-ChildItem $lnkDirs -Recurse -Filter *.lnk -ErrorAction SilentlyContinue | ForEach-Object {
    [pscustomobject]@{ Name = $_.BaseName; Target = $wsh.CreateShortcut($_.FullName).TargetPath; Shortcut = $_.FullName }
}
$shortcuts | Export-Csv (Join-Path $Pub 'shortcuts.csv') -NoTypeInformation -Encoding UTF8

Log 'Autostart + running processes'
Get-CimInstance Win32_StartupCommand -ErrorAction SilentlyContinue |
    Select-Object Name, Command, Location |
    Export-Csv (Join-Path $Pub 'autostart.csv') -NoTypeInformation -Encoding UTF8
$procs = Get-Process | Where-Object Path | Select-Object Name, Path -Unique | Sort-Object Name
$procs | Export-Csv (Join-Path $Pub 'processes.csv') -NoTypeInformation -Encoding UTF8

if (Get-Command code -ErrorAction SilentlyContinue) {
    Log 'VS Code extensions'
    code --list-extensions | Out-File (Join-Path $Pub 'vscode-extensions.txt') -Encoding UTF8
}

# ---------------------------------------------------------------- 2. VPN и рабочие конфиги
Log 'Looking for VPN clients'
$vpnPattern = 'VPN|WireGuard|Throne|Nekoray|sing-box|v2ray|Hiddify|Amnezia|Outline|Clash|OpenVPN|AnyConnect|Cisco Secure|Forti|Check Point|GlobalProtect|Pulse|Ivanti|Kerio|Tabby'
$candidates = @()
$candidates += $programs  | Where-Object { $_.DisplayName -match $vpnPattern } | ForEach-Object { "program:  $($_.DisplayName)  [$($_.InstallLocation)]" }
$candidates += $shortcuts | Where-Object { $_.Name -match $vpnPattern -or $_.Target -match $vpnPattern } | ForEach-Object { "shortcut: $($_.Name)  ->  $($_.Target)" }
$candidates += $procs     | Where-Object { $_.Path -match $vpnPattern } | ForEach-Object { "process:  $($_.Name)  ->  $($_.Path)" }
$candidates | Sort-Object -Unique | Out-File (Join-Path $Pub 'vpn-candidates.txt') -Encoding UTF8

# Throne / Nekoray: конфиг лежит в папке config рядом с exe (портативный режим)
$throneExe = @()
$throneExe += $procs     | Where-Object { $_.Path -match '\\(throne|nekoray)\.exe$' } | ForEach-Object Path
$throneExe += $shortcuts | Where-Object { $_.Target -match '\\(throne|nekoray)\.exe$' } | ForEach-Object Target
if (-not $throneExe) {
    $searchRoots = @($env:USERPROFILE, $env:ProgramFiles, ${env:ProgramFiles(x86)}, 'D:\') | Where-Object { $_ -and (Test-Path $_) }
    $throneExe += Get-ChildItem $searchRoots -Recurse -Depth 4 -Include 'throne.exe', 'nekoray.exe' -ErrorAction SilentlyContinue | ForEach-Object FullName
}
$i = 0
foreach ($exe in ($throneExe | Sort-Object -Unique)) {
    $dir = Split-Path $exe
    Save-Secret (Join-Path $dir 'config') "throne\$i-config"
    $i++
}
foreach ($d in "$env:APPDATA\Throne", "$env:APPDATA\nekoray", "$env:LOCALAPPDATA\Throne") { Save-Secret $d ('throne\appdata-' + (Split-Path $d -Leaf)) }
if (-not $throneExe) { Note 'Throne/Nekoray не найден автоматически: найдите папку программы и скопируйте её подпапку config в secrets\throne вручную.' }
Note 'Throne: дополнительно выделите все профили -> ПКМ -> Share/Copy link и сохраните ссылки в secrets\throne\links.txt'

# WireGuard для Windows хранит туннели зашифрованными (DPAPI) — копировать файлы бесполезно
if (Test-Path "$env:ProgramFiles\WireGuard\wireguard.exe") {
    Note 'WireGuard: в окне WireGuard нажмите Export tunnels to zip (стрелка рядом с Add Tunnel) и сохраните zip в secrets\wireguard\'
}

# Встроенный VPN Windows
$builtinVpn = @(Get-VpnConnection -ErrorAction SilentlyContinue) + @(Get-VpnConnection -AllUserConnection -ErrorAction SilentlyContinue)
if ($builtinVpn) {
    $builtinVpn | Select-Object Name, ServerAddress, TunnelType, AuthenticationMethod, SplitTunneling |
        Export-Csv (Join-Path $Sec 'windows-vpn.csv') -NoTypeInformation -Encoding UTF8
    $saved.Add('windows-vpn.csv  <-  Get-VpnConnection')
}
Save-Secret "$env:APPDATA\Microsoft\Network\Connections\Pbk\rasphone.pbk" 'windows-vpn\user-rasphone.pbk'
Save-Secret "$env:ProgramData\Microsoft\Network\Connections\Pbk\rasphone.pbk" 'windows-vpn\all-rasphone.pbk'

# OpenVPN (GUI и Connect), AmneziaVPN
Save-Secret "$env:USERPROFILE\OpenVPN\config" 'openvpn\user-config'
Save-Secret "$env:ProgramFiles\OpenVPN\config" 'openvpn\program-config'
Save-Secret "$env:APPDATA\OpenVPN Connect\profiles" 'openvpn\connect-profiles'
if (Test-Path "$env:ProgramFiles\AmneziaVPN") { Note 'AmneziaVPN: экспортируйте подключения из самого приложения (Поделиться -> файл) в secrets\amnezia\' }

# Tabby: config.yaml — профили SSH, хосты. Если включён vault, понадобится его мастер-пароль
$tabbyDir = "$env:APPDATA\tabby"
if (Test-Path $tabbyDir) {
    Get-ChildItem $tabbyDir -Filter *.yaml -ErrorAction SilentlyContinue | ForEach-Object { Save-Secret $_.FullName "tabby\$($_.Name)" }
    Save-Secret "$tabbyDir\plugins\package.json" 'tabby\plugins-package.json'
    Note 'Tabby: если в настройках включён Vault — запишите его мастер-пароль, без него сохранённые пароли не расшифровать.'
}

# SSH, git, hosts, переменные окружения, VS Code
Save-Secret "$env:USERPROFILE\.ssh" 'ssh'
Save-Secret "$env:USERPROFILE\.gitconfig" 'gitconfig'
Save-Secret "$env:SystemRoot\System32\drivers\etc\hosts" 'hosts'
[Environment]::GetEnvironmentVariables('User').GetEnumerator() | Sort-Object Name |
    ForEach-Object { "$($_.Name)=$($_.Value)" } | Out-File (Join-Path $Sec 'env-user.txt') -Encoding UTF8
foreach ($f in 'settings.json', 'keybindings.json', 'snippets') { Save-Secret "$env:APPDATA\Code\User\$f" "vscode\$f" }

# Wi-Fi: с правами администратора пароли сохраняются открытым текстом
Log 'Wi-Fi profiles'
New-Item -ItemType Directory -Force -Path (Join-Path $Sec 'wifi') | Out-Null
if ($isAdmin) { netsh wlan export profile key=clear folder="$Sec\wifi" | Out-Null }
else          { netsh wlan export profile folder="$Sec\wifi" | Out-Null }

# ---------------------------------------------------------------- 3. Размеры папок
function Get-DirSize([string]$Path) {
    $total = [long]0; $count = 0
    $stack = New-Object System.Collections.Generic.Stack[string]
    $stack.Push($Path)
    while ($stack.Count) {
        $d = New-Object IO.DirectoryInfo ($stack.Pop())
        try {
            foreach ($e in $d.EnumerateFileSystemInfos()) {
                # skip junctions/symlinks and OneDrive placeholders: no loops, no double counting
                if ($e.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
                if ($e -is [IO.DirectoryInfo]) { $stack.Push($e.FullName) } else { $total += $e.Length; $count++ }
            }
        } catch { }
    }
    [pscustomobject]@{ Path = $Path; SizeGB = [math]::Round($total / 1GB, 2); Files = $count }
}

if (-not $SkipSizes) {
    Log 'Folder sizes (can take 10-30 min)...'
    $roots = @($env:USERPROFILE, $env:APPDATA, $env:LOCALAPPDATA, 'C:\', 'D:\') | Where-Object { Test-Path $_ }
    $dirs = foreach ($r in $roots) {
        Get-ChildItem -LiteralPath $r -Directory -Force -ErrorAction SilentlyContinue |
            Where-Object { -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) } |
            Where-Object { $_.FullName -notmatch '^C:\\(Windows|Users|\$Recycle\.Bin|System Volume Information|Recovery)$' } |
            Where-Object { $_.FullName -ne "$env:USERPROFILE\AppData" }   # AppData считается отдельно через Roaming/Local
    }
    $n = 0
    $sizes = foreach ($d in $dirs) {
        $n++; Write-Progress -Activity 'Folder sizes' -Status $d.FullName -PercentComplete ($n * 100 / $dirs.Count)
        Get-DirSize $d.FullName
    }
    Write-Progress -Activity 'Folder sizes' -Completed
    $sizes | Sort-Object SizeGB -Descending | Export-Csv (Join-Path $Pub 'folder-sizes.csv') -NoTypeInformation -Encoding UTF8
    Get-PSDrive -PSProvider FileSystem | Select-Object Name, @{ n = 'UsedGB'; e = { [math]::Round($_.Used / 1GB, 1) } }, @{ n = 'FreeGB'; e = { [math]::Round($_.Free / 1GB, 1) } } |
        Export-Csv (Join-Path $Pub 'drives.csv') -NoTypeInformation -Encoding UTF8
    Write-Host ''
    Write-Host 'Top 25 folders:' -ForegroundColor Green
    $sizes | Sort-Object SizeGB -Descending | Select-Object -First 25 | Format-Table -AutoSize
}

# ---------------------------------------------------------------- 4. Итог
$readme = @(
    'ArchTry inventory ' + $stamp
    ''
    'public\  - можно отправить Claude (public.zip)'
    'secrets\ - НЕ отправлять, НЕ класть в git. Перенести на внешний диск, лучше в архив с паролем.'
    ''
    'Сохранено в secrets:'
) + ($saved | ForEach-Object { '  ' + $_ }) + @('', 'Сделать вручную:') + ($notes | ForEach-Object { '  - ' + $_ })
$readme | Out-File (Join-Path $Out 'README.txt') -Encoding UTF8
$notes  | Out-File (Join-Path $Pub 'manual-steps.txt') -Encoding UTF8

Compress-Archive -Path "$Pub\*" -DestinationPath (Join-Path $Out 'public.zip') -Force

Write-Host ''
Write-Host "Done: $Out" -ForegroundColor Green
Write-Host 'Send public.zip to Claude. Keep secrets\ offline!' -ForegroundColor Green
if ($notes.Count) { Write-Host 'Manual steps:' -ForegroundColor Yellow; $notes | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow } }
