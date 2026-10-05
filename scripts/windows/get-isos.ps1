<#
  Скачать актуальные образы для установки (ArchTry):
    - Arch Linux ISO (последний, с зеркала Яндекса) + проверка SHA256
    - Ventoy для Windows (последний релиз с GitHub) + проверка SHA256
    - Windows 11 ISO (официальная ссылка Microsoft через Fido) — нужен VPN
    - sing-box для Linux (запасной бинарник для VPN в live-Arch) → <Dest>\archtry\sing-box

  Запуск (PowerShell, админ не нужен):
    powershell -ExecutionPolicy Bypass -File .\get-isos.ps1
    powershell -ExecutionPolicy Bypass -File .\get-isos.ps1 -Dest E:\iso -SkipWindows
    powershell -ExecutionPolicy Bypass -File .\get-isos.ps1 -Proxy http://127.0.0.1:2080   # через Throne без TUN

  Если скачивание прервалось — просто запустить ещё раз: curl докачает с места остановки.
#>

param(
    [string]$Dest = 'E:\iso',
    [string]$Proxy = '',              # прокси Throne (порт смотреть в настройках Throne), если не включён TUN-режим
    [string]$WinLang = 'Russian',     # язык Windows 11
    [switch]$SkipArch,
    [switch]$SkipVentoy,
    [switch]$SkipWindows,
    [switch]$SkipSingBox
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
New-Item -ItemType Directory -Force -Path $Dest | Out-Null
$curlProxy = @(); if ($Proxy) { $curlProxy = @('-x', $Proxy) }

function Get-File([string]$Url, [string]$OutFile, [switch]$Resume) {
    Write-Host "[*] $Url" -ForegroundColor Cyan
    # -C - : resume partial download (big files only); --retry: survive short network drops
    $resumeArg = @(); if ($Resume) { $resumeArg = @('-C', '-') }
    & curl.exe -L --fail --retry 5 --retry-delay 5 @resumeArg @curlProxy -o $OutFile $Url
    if ($LASTEXITCODE -ne 0) { throw "curl failed ($LASTEXITCODE): $Url" }
}

function Test-Hash([string]$File, [string]$Expected, [switch]$Quiet) {
    if (-not (Test-Path -LiteralPath $File)) { return $false }
    $actual = (Get-FileHash -LiteralPath $File -Algorithm SHA256).Hash
    $ok = $actual -ieq $Expected
    if (-not $Quiet) {
        if ($ok) { Write-Host "[OK] SHA256 $([IO.Path]::GetFileName($File))" -ForegroundColor Green }
        else { Write-Host "[FAIL] SHA256 mismatch: $File`n  expected $Expected`n  actual   $actual" -ForegroundColor Red }
    }
    return $ok
}

# ---------------------------------------------------------------- Arch Linux
if (-not $SkipArch) {
    $base = 'https://mirror.yandex.ru/archlinux/iso/latest'
    $iso = Join-Path $Dest 'archlinux-x86_64.iso'
    $sums = Join-Path $Dest 'archlinux-sha256sums.txt'
    Get-File "$base/sha256sums.txt" $sums
    $line = Get-Content $sums | Where-Object { $_ -match '\sarchlinux-(\d{4}\.\d{2}\.\d{2}-)?x86_64\.iso$' } | Select-Object -First 1
    $expected = if ($line) { ($line -split '\s+')[0] } else { $null }
    if ($expected -and (Test-Hash $iso $expected -Quiet)) { Write-Host '[OK] Arch ISO already downloaded' -ForegroundColor Green }
    else {
        Get-File "$base/archlinux-x86_64.iso" $iso -Resume
        if ($expected) { [void](Test-Hash $iso $expected) } else { Write-Host '[!] archlinux hash not found in sha256sums.txt' -ForegroundColor Yellow }
    }
    $ver = Get-Content $sums | Select-String -Pattern 'archlinux-(\d{4}\.\d{2}\.\d{2})-x86_64\.iso' | Select-Object -First 1
    if ($ver) { Write-Host "    Arch version: $($ver.Matches[0].Groups[1].Value)" }
}

# ---------------------------------------------------------------- Ventoy
if (-not $SkipVentoy) {
    $irm = @{ Uri = 'https://api.github.com/repos/ventoy/Ventoy/releases/latest' }
    if ($Proxy) { $irm.Proxy = $Proxy }
    $rel = Invoke-RestMethod @irm
    $asset = $rel.assets | Where-Object { $_.name -match '^ventoy-.*-windows\.zip$' } | Select-Object -First 1
    $zip = Join-Path $Dest $asset.name
    Get-File $asset.browser_download_url $zip
    $shaAsset = $rel.assets | Where-Object { $_.name -eq 'sha256.txt' } | Select-Object -First 1
    if ($shaAsset) {
        $shaFile = Join-Path $Dest 'ventoy-sha256.txt'
        Get-File $shaAsset.browser_download_url $shaFile
        $line = Get-Content $shaFile | Where-Object { $_ -match [regex]::Escape($asset.name) } | Select-Object -First 1
        if ($line) { [void](Test-Hash $zip ($line -split '\s+')[0]) }
    }
    Expand-Archive -LiteralPath $zip -DestinationPath (Join-Path $Dest 'ventoy') -Force
    Write-Host "    Ventoy $($rel.tag_name): $(Join-Path $Dest 'ventoy')\...\Ventoy2Disk.exe"
}

# ---------------------------------------------------------------- sing-box (Linux, for live-Arch VPN)
if (-not $SkipSingBox) {
    $irm = @{ Uri = 'https://api.github.com/repos/SagerNet/sing-box/releases/latest' }
    if ($Proxy) { $irm.Proxy = $Proxy }
    $rel = Invoke-RestMethod @irm
    $asset = $rel.assets | Where-Object { $_.name -match '^sing-box-[\d.]+-linux-amd64\.tar\.gz$' } | Select-Object -First 1
    $tgz = Join-Path $Dest $asset.name
    Get-File $asset.browser_download_url $tgz
    $sbDir = Join-Path $Dest 'archtry'
    New-Item -ItemType Directory -Force -Path $sbDir | Out-Null
    & tar.exe -xzf $tgz -C $Dest                       # tar is built into Windows 10/11
    $extracted = Join-Path (Join-Path $Dest ($asset.name -replace '\.tar\.gz$', '')) 'sing-box'
    Copy-Item -LiteralPath $extracted -Destination (Join-Path $sbDir 'sing-box') -Force
    Write-Host "    sing-box $($rel.tag_name) for Linux: $sbDir\sing-box"
}

# ---------------------------------------------------------------- Windows 11
if (-not $SkipWindows) {
    # Fido (автор Rufus) получает у Microsoft официальную временную ссылку на ISO
    $fido = Join-Path $Dest 'Fido.ps1'
    Get-File 'https://raw.githubusercontent.com/pbatard/Fido/master/Fido.ps1' $fido
    Write-Host '[*] Asking Microsoft for Windows 11 download link (needs VPN)...' -ForegroundColor Cyan
    $ErrorActionPreference = 'Continue'   # Fido writes progress to stderr; do not treat it as fatal
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $fido -Win 11 -Rel Latest -Ed Pro -Lang $WinLang -Arch x64 -GetUrl 2>&1
    $url = $out | ForEach-Object { "$_" } | Where-Object { $_ -match '^https://' } | Select-Object -Last 1
    if ($url) {
        Get-File $url (Join-Path $Dest "Win11_${WinLang}_x64.iso") -Resume
        Write-Host '    SHA256 for Windows ISO: compare with the table on microsoft.com/software-download/windows11' -ForegroundColor Yellow
        Get-FileHash (Join-Path $Dest "Win11_${WinLang}_x64.iso") -Algorithm SHA256 | Format-List Hash
    } else {
        Write-Host '[!] Microsoft did not give a link (often blocks by region/VPN). Fido output:' -ForegroundColor Yellow
        $out | ForEach-Object { Write-Host "    $_" }
        Write-Host '    Manual: https://www.microsoft.com/software-download/windows11 -> "Download Windows 11 Disk Image (ISO)"' -ForegroundColor Yellow
    }
}

Write-Host ''
Get-ChildItem $Dest -File | Select-Object Name, @{ n = 'MB'; e = { [math]::Round($_.Length / 1MB) } } | Format-Table -AutoSize
