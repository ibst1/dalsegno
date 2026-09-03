# build.ps1 - builds the portable DalSegno Window Manager release zip into dist\.
# Downloads the toolchain (AutoHotkey v2 base, VirtualDesktopAccessor.dll)
# into build\ on first run and caches it there. Works in Windows PowerShell 5.1
# and PowerShell 7 (used by the GitHub Actions release workflow).
#
# The zip ships the UNMODIFIED official AutoHotkey64.exe renamed to
# DalSegno.exe, next to the plain-text scripts: run with no arguments, the
# interpreter loads the script matching its own name (DalSegno.ahk). The
# arrow helper runs uncompiled via A_AhkPath. Ahk2Exe-compiled output was a
# unique unsigned binary per release and kept tripping Defender's cloud/ML
# heuristics on managed machines; the stock interpreter stays byte-identical
# to the official release and keeps its reputation.
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$root = $PSScriptRoot
$tools = Join-Path $root 'build'
$dist = Join-Path $root 'dist'
New-Item -ItemType Directory -Force $tools | Out-Null

# version from the script header ("; DalSegno Window Manager — vX.Y.Z ...")
$header = (Get-Content (Join-Path $root 'DalSegno.ahk') -TotalCount 5) -join ' '
$version = if ($header -match 'v(\d+\.\d+\.\d+)') { $Matches[1] } else { '0.0.0' }
Write-Host "Building DalSegno Window Manager $version"

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
    $done = $false
    foreach ($i in 1..5) {
        try {
            Remove-Item $dist -Recurse -Force -ErrorAction Stop
            $done = $true
            break
        } catch {
            Start-Sleep -Seconds 2
        }
    }
    if (-not $done) { throw "Could not clear $dist - is DalSegno.exe running or the folder open?" }
}
foreach ($sub in 'icons', 'src', 'ui', 'lib') {
    New-Item -ItemType Directory -Force (Join-Path $dist $sub) | Out-Null
}

# the renamed stock interpreter auto-loads DalSegno.ahk beside it
Copy-Item $base (Join-Path $dist 'DalSegno.exe')
Copy-Item (Join-Path $root 'DalSegno.ahk') $dist
Copy-Item (Join-Path $root 'DalSegnoArrow.ahk') $dist
Copy-Item (Join-Path $root 'app.ico') $dist
Copy-Item (Join-Path $root 'src\*.ahk') (Join-Path $dist 'src')
Copy-Item (Join-Path $root 'ui\*') (Join-Path $dist 'ui')
Copy-Item (Join-Path $root 'lib\*') (Join-Path $dist 'lib')
Copy-Item (Join-Path $root 'ComVar.ahk') $dist
Copy-Item (Join-Path $root 'Promise.ahk') $dist
Copy-Item (Join-Path $root 'icons\*.ico') (Join-Path $dist 'icons')
Copy-Item $dll $dist
Copy-Item (Join-Path $root 'THIRD-PARTY.txt') $dist

$zip = Join-Path $dist "DalSegno-$version.zip"
$content = @('DalSegno.exe', 'DalSegno.ahk', 'DalSegnoArrow.ahk', 'app.ico', 'src', 'ui', 'lib'
    , 'ComVar.ahk', 'Promise.ahk', 'icons', 'VirtualDesktopAccessor.dll', 'THIRD-PARTY.txt') | ForEach-Object { Join-Path $dist $_ }
Compress-Archive -Path $content -DestinationPath $zip -Force
Write-Host "Done: $zip"
