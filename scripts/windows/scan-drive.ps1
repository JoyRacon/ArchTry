<#
  Анализ внешнего диска перед стиранием старого бэкапа (ArchTry).
  Только читает, ничего не меняет.

  Запуск (PowerShell, админ не нужен):
    powershell -ExecutionPolicy Bypass -File .\scan-drive.ps1 -Drive E

  Результат: Desktop\drive-scan-<буква>-<дата>.txt — его можно отправить Claude.
  Внутри только имена папок, размеры, типы файлов и даты; содержимое файлов не читается.
#>

param(
    [Parameter(Mandatory = $true)][string]$Drive,   # буква диска, например E
    [int]$Depth = 3                                 # насколько глубоко показывать дерево папок
)

$Drive = $Drive.TrimEnd(':', '\')
$root = "${Drive}:\"
if (-not (Test-Path $root)) { Write-Host "Диск $root не найден" -ForegroundColor Red; exit 1 }

$stamp = Get-Date -Format 'yyyy-MM-dd_HHmm'
$report = Join-Path ([Environment]::GetFolderPath('Desktop')) "drive-scan-$Drive-$stamp.txt"
$lines = New-Object System.Collections.Generic.List[string]
function Out-Line([string]$s = '') { $lines.Add($s); Write-Host $s }
function Fmt([long]$b) { if ($b -ge 1GB) { '{0:N1} GB' -f ($b / 1GB) } elseif ($b -ge 1MB) { '{0:N0} MB' -f ($b / 1MB) } else { '{0:N0} KB' -f ($b / 1KB) } }

# ---------------------------------------------------------------- Том и физический диск
Out-Line "=== VOLUME $root"
$vol = Get-Volume -DriveLetter $Drive -ErrorAction SilentlyContinue
if ($vol) {
    Out-Line ("FileSystem: {0}   Label: {1}   Size: {2}   Free: {3}" -f $vol.FileSystemType, $vol.FileSystemLabel, (Fmt $vol.Size), (Fmt $vol.SizeRemaining))
    $part = Get-Partition -DriveLetter $Drive -ErrorAction SilentlyContinue
    if ($part) {
        $disk = Get-Disk -Number $part.DiskNumber
        Out-Line ("Disk: {0}   Bus: {1}   Total: {2}   PartitionStyle: {3}   Partitions on disk: {4}" -f $disk.FriendlyName, $disk.BusType, (Fmt $disk.Size), $disk.PartitionStyle, $disk.NumberOfPartitions)
        Get-Partition -DiskNumber $part.DiskNumber | ForEach-Object {
            Out-Line ("  partition {0}: {1}  letter={2}  type={3}" -f $_.PartitionNumber, (Fmt $_.Size), $_.DriveLetter, $_.Type)
        }
    }
}
$bl = Get-BitLockerVolume -MountPoint "${Drive}:" -ErrorAction SilentlyContinue
if ($bl) { Out-Line ("BitLocker: {0}" -f $bl.ProtectionStatus) }
Out-Line

# ---------------------------------------------------------------- Обход всех файлов
Write-Host 'Scanning files...' -ForegroundColor Cyan
$dirSize = @{}        # размер каждой папки до глубины $Depth (включая вложенное)
$extStat = @{}        # статистика по расширениям
$years = @{}          # распределение по году изменения
$big = New-Object System.Collections.Generic.List[object]
$total = [long]0; $files = 0; $errors = 0
$minDate = [datetime]::MaxValue; $maxDate = [datetime]::MinValue

$stack = New-Object System.Collections.Generic.Stack[string]
$stack.Push($root)
while ($stack.Count) {
    $d = New-Object IO.DirectoryInfo ($stack.Pop())
    try {
        foreach ($e in $d.EnumerateFileSystemInfos()) {
            if ($e.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
            if ($e -is [IO.DirectoryInfo]) { $stack.Push($e.FullName); continue }
            $len = $e.Length; $total += $len; $files++
            # add size to every ancestor folder up to $Depth levels
            $rel = $e.DirectoryName.Substring($root.Length).Trim('\')
            if ($rel) {
                $parts = $rel.Split('\'); $acc = ''
                for ($i = 0; $i -lt [math]::Min($parts.Count, $Depth); $i++) {
                    $acc = if ($acc) { "$acc\$($parts[$i])" } else { $parts[$i] }
                    $dirSize[$acc] = [long]$dirSize[$acc] + $len
                }
            }
            $ext = $e.Extension.ToLower(); if (-not $ext) { $ext = '(none)' }
            if (-not $extStat.ContainsKey($ext)) { $extStat[$ext] = @{ Count = 0; Bytes = [long]0 } }
            $extStat[$ext].Count++; $extStat[$ext].Bytes += $len
            $t = $e.LastWriteTime
            if ($t -lt $minDate) { $minDate = $t }; if ($t -gt $maxDate) { $maxDate = $t }
            $years[$t.Year] = [int]$years[$t.Year] + 1
            if ($len -ge 1GB) { $big.Add([pscustomobject]@{ Size = $len; Path = $e.FullName; Date = $t }) }
        }
    } catch { $errors++ }
}

Out-Line "=== SUMMARY"
Out-Line ("Files: {0:N0}   Total: {1}   Unreadable folders: {2}" -f $files, (Fmt $total), $errors)
if ($files) { Out-Line ("Oldest file: {0:yyyy-MM-dd}   Newest file: {1:yyyy-MM-dd}" -f $minDate, $maxDate) }
Out-Line

# ---------------------------------------------------------------- Распознать формат бэкапа
Out-Line '=== BACKUP FORMAT HINTS'
$hints = @()
if (Test-Path "${root}WindowsImageBackup") {
    $hints += 'WindowsImageBackup: образ системы Windows (.vhdx) — можно подключить как диск'
    Get-ChildItem "${root}WindowsImageBackup" -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        $pc = $_.Name
        Get-ChildItem $_.FullName -Directory -Filter 'Backup*' -ErrorAction SilentlyContinue | ForEach-Object {
            $hints += "  PC=$pc  $($_.Name)"
            Get-ChildItem $_.FullName -Filter *.vhd* -ErrorAction SilentlyContinue | ForEach-Object { $hints += "    $($_.Name)  $(Fmt $_.Length)" }
        }
    }
}
if (Test-Path "${root}FileHistory") { $hints += 'FileHistory: История файлов Windows — обычные файлы с датой в имени' }
$known = @{
    '.tib' = 'Acronis True Image (нужен Acronis)'; '.tibx' = 'Acronis True Image (нужен Acronis)'
    '.mrimg' = 'Macrium Reflect (нужен Macrium)'; '.mrbak' = 'Macrium Reflect (нужен Macrium)'
    '.vhd' = 'виртуальный диск (подключается в Windows)'; '.vhdx' = 'виртуальный диск (подключается в Windows)'
    '.wim' = 'образ Windows WIM'; '.esd' = 'образ Windows ESD'; '.gho' = 'Norton Ghost'; '.adi' = 'AOMEI Backupper'
    '.pbd' = 'Paragon Backup'; '.pvhd' = 'Paragon Backup'; '.img' = 'образ диска'; '.iso' = 'образ диска ISO'
    '.zip' = 'архив'; '.7z' = 'архив'; '.rar' = 'архив'; '.bak' = 'файл бэкапа'
}
foreach ($k in $known.Keys) { if ($extStat.ContainsKey($k)) { $hints += ("{0,-7} x{1,-5} {2,10}  {3}" -f $k, $extStat[$k].Count, (Fmt $extStat[$k].Bytes), $known[$k]) } }
if (-not $hints) { $hints = @('специальных форматов не найдено — похоже на обычную копию файлов') }
$hints | ForEach-Object { Out-Line $_ }
Out-Line

# ---------------------------------------------------------------- Что внутри по смыслу
$groups = [ordered]@{
    'Фото'      = '.jpg', '.jpeg', '.png', '.heic', '.cr2', '.nef', '.arw', '.dng', '.raw', '.webp', '.gif', '.bmp'
    'Видео'     = '.mp4', '.mov', '.avi', '.mkv', '.wmv', '.m4v', '.3gp'
    'Музыка'    = '.mp3', '.flac', '.wav', '.m4a', '.ogg', '.aac'
    'Документы' = '.pdf', '.doc', '.docx', '.xls', '.xlsx', '.ppt', '.pptx', '.txt', '.odt', '.rtf', '.md', '.vsdx'
    'Проекты DAW' = '.flp', '.als', '.ngrr', '.nksn'
    '3D'        = '.blend', '.stl', '.3mf', '.obj', '.fbx', '.gcode'
    'Код'       = '.py', '.js', '.ts', '.cs', '.cpp', '.java', '.go', '.php', '.html', '.css'
    'Программы' = '.exe', '.msi', '.dll'
}
Out-Line '=== CONTENT BY TYPE'
foreach ($g in $groups.Keys) {
    $c = 0; $b = [long]0
    foreach ($x in $groups[$g]) { if ($extStat.ContainsKey($x)) { $c += $extStat[$x].Count; $b += $extStat[$x].Bytes } }
    if ($c) { Out-Line ("{0,-12} {1,8:N0} files  {2,10}" -f $g, $c, (Fmt $b)) }
}
Out-Line

Out-Line '=== TOP 25 EXTENSIONS BY SIZE'
$extStat.GetEnumerator() | Sort-Object { $_.Value.Bytes } -Descending | Select-Object -First 25 | ForEach-Object {
    Out-Line ("{0,-12} {1,8:N0} files  {2,10}" -f $_.Key, $_.Value.Count, (Fmt $_.Value.Bytes))
}
Out-Line

Out-Line '=== FILES BY YEAR (last modified)'
$years.GetEnumerator() | Sort-Object Key | ForEach-Object { Out-Line ("{0}  {1,8:N0}" -f $_.Key, $_.Value) }
Out-Line

Out-Line "=== FOLDER TREE (depth $Depth, folders >= 100 MB)"
$dirSize.GetEnumerator() | Where-Object { $_.Value -ge 100MB } | Sort-Object Key | ForEach-Object {
    $lvl = ($_.Key.Split('\').Count - 1)
    Out-Line ("{0,10}  {1}{2}" -f (Fmt $_.Value), ('    ' * $lvl), ($_.Key.Split('\')[-1]))
}
Out-Line

Out-Line '=== FILES >= 1 GB'
$big | Sort-Object Size -Descending | Select-Object -First 40 | ForEach-Object {
    Out-Line ("{0,10}  {1:yyyy-MM-dd}  {2}" -f (Fmt $_.Size), $_.Date, $_.Path)
}

$lines | Out-File $report -Encoding UTF8
Write-Host ''
Write-Host "Report: $report" -ForegroundColor Green
