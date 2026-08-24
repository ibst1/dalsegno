# build.ps1 - builds the portable DeskPilot release zip into dist\.
# Downloads the toolchain (AutoHotkey v2 base, VirtualDesktopAccessor.dll)
# into build\ on first run and caches it there. Works in Windows PowerShell 5.1
# and PowerShell 7 (used by the GitHub Actions release workflow).
#
# The zip ships the UNMODIFIED official AutoHotkey64.exe renamed to
# DeskPilot.exe, next to the plain-text scripts: run with no arguments, the
# interpreter loads the script matching its own name (DeskPilot.ahk). The
# arrow helpers run uncompiled via A_AhkPath, so DeskPilotArrow.exe is no
# longer built. Ahk2Exe-compiled output was a unique unsigned binary per
# release and kept tripping Defender's cloud/ML heuristics on managed
# machines; the stock interpreter stays byte-identical to the official
# release and keeps its reputation.
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$root = $PSScriptRoot
$tools = Join-Path $root 'build'
$dist = Join-Path $root 'dist'
New-Item -ItemType Directory -Force $tools | Out-Null

# version from the script header ("; DeskPilot - vX.Y.Z ...")
$header = (Get-Content (Join-Path $root 'DeskPilot.ahk') -TotalCount 5) -join ' '
$version = if ($header -match 'v(\d+\.\d+\.\d+)') { $Matches[1] } else { '0.0.0' }
Write-Host "Building DeskPilot $version"

$base = Join-Path $tools 'base\AutoHotkey64.exe'
if (-not (Test-Path $base)) {
    Write-Host 'Downloading AutoHotkey v2 base...'
    $rels = Invoke-RestMethod 'https://api.github.com/repos/AutoHotkey/AutoHotkey/releases'
    $v2 = $rels | Where-Object { $_.tag_name -like 'v2.0*' } | Select-Object -First 1
    $asset = $v2.assets | Where-Object { $_.name -like 'AutoHotkey_2*.zip' } | Select-Object -First 1
    Invoke-WebRequest $asset.browser_download_url -OutFile (Join-Path $tools 'ahk2.zip')
    Expand-Archive (Join-Path $tools 'ahk2.zip') (Join-Path $tools 'base') -Force
}

$dll = Join-Path $tools 'VirtualDesktopAccessor.dll'
if (-not (Test-Path $dll)) {
    Write-Host 'Downloading VirtualDesktopAccessor.dll...'
    Invoke-WebRequest 'https://github.com/Ciantic/VirtualDesktopAccessor/releases/latest/download/VirtualDesktopAccessor.dll' -OutFile $dll
}

# clear dist with retries - OneDrive/AV can hold freshly written files briefly
if (Test-Path $dist) {
    $klart = $false
    foreach ($i in 1..5) {
        try {
            Remove-Item $dist -Recurse -Force -ErrorAction Stop
            $klart = $true
            break
        } catch {
            Start-Sleep -Seconds 2
        }
    }
    if (-not $klart) { throw "Could not clear $dist - is DeskPilot.exe running or the folder open?" }
}
New-Item -ItemType Directory -Force (Join-Path $dist 'icons') | Out-Null

# the renamed stock interpreter auto-loads DeskPilot.ahk beside it;
# the arrow helpers are launched uncompiled via A_AhkPath
Copy-Item $base (Join-Path $dist 'DeskPilot.exe')
Copy-Item (Join-Path $root 'DeskPilot.ahk') $dist
Copy-Item (Join-Path $root 'DeskPilotArrow.ahk') $dist

Copy-Item (Join-Path $root 'icons\*.ico') (Join-Path $dist 'icons')
Copy-Item $dll $dist
Copy-Item (Join-Path $root 'THIRD-PARTY.txt') $dist

$zip = Join-Path $dist "DeskPilot-$version.zip"
$innehall = @('DeskPilot.exe', 'DeskPilot.ahk', 'DeskPilotArrow.ahk', 'icons', 'VirtualDesktopAccessor.dll', 'THIRD-PARTY.txt') | ForEach-Object { Join-Path $dist $_ }
Compress-Archive -Path $innehall -DestinationPath $zip -Force
Write-Host "Done: $zip"
