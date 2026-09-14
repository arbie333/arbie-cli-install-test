# REFERENCE COPY — not the live script. snaplogic-cli is private, so no one
# irm's this file from here. The canonical, user-facing copy lives at
# https://github.com/arbie333/arbie-cli-install-test/blob/main/install.ps1 —
# that's the one actual `irm | iex` installs run. Land fixes here first for
# PR review, then port them to that repo's install.ps1 by hand; this file
# does not auto-sync there.
#
# Installs the sl CLI (SnapLogic CLI) from the latest (or pinned) release at
# https://github.com/arbie333/arbie-cli-install-test/releases
#
# Usage:
#   irm https://raw.githubusercontent.com/arbie333/arbie-cli-install-test/main/install.ps1 | iex
#
# Env vars:
#   SL_VERSION      release tag to install, e.g. v1.2.3 (default: latest)
#   SL_INSTALL_DIR  directory to install the binary into (default: $env:LOCALAPPDATA\sl\bin)

$ErrorActionPreference = "Stop"

$Repo = "arbie333/arbie-cli-install-test"
$BaseUrl = "https://github.com/$Repo/releases"
$Version = if ($env:SL_VERSION) { $env:SL_VERSION } else { "latest" }

function Fail($Message) {
    Write-Error "error: $Message"
    exit 1
}

function Get-Arch {
    switch ($env:PROCESSOR_ARCHITECTURE) {
        "AMD64" { return "amd64" }
        "ARM64" { return "arm64" }
        default { Fail "unsupported architecture: $($env:PROCESSOR_ARCHITECTURE). Download a release manually from $BaseUrl" }
    }
}

$Arch = Get-Arch
$Asset = "sl_windows_${Arch}.zip"

if ($Version -eq "latest") {
    $DownloadPath = "latest/download"
} else {
    $DownloadPath = "download/$Version"
}

$TmpDir = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
New-Item -ItemType Directory -Path $TmpDir | Out-Null
try {
    $AssetPath = Join-Path $TmpDir $Asset
    $ChecksumsPath = Join-Path $TmpDir "checksums.txt"

    Write-Host "Downloading sl (windows/$Arch, $Version)..."
    try {
        Invoke-WebRequest -Uri "$BaseUrl/$DownloadPath/$Asset" -OutFile $AssetPath -UseBasicParsing
    } catch {
        Fail "download failed: $BaseUrl/$DownloadPath/$Asset"
    }
    try {
        Invoke-WebRequest -Uri "$BaseUrl/$DownloadPath/checksums.txt" -OutFile $ChecksumsPath -UseBasicParsing
    } catch {
        Fail "download failed: $BaseUrl/$DownloadPath/checksums.txt"
    }

    $ExpectedLine = Select-String -Path $ChecksumsPath -Pattern ("$([regex]::Escape($Asset))$") | Select-Object -First 1
    if (-not $ExpectedLine) {
        Fail "checksum entry for $Asset not found in checksums.txt"
    }
    $ExpectedHash = ($ExpectedLine.Line -split '\s+')[0]
    $ActualHash = (Get-FileHash -Path $AssetPath -Algorithm SHA256).Hash
    if ($ActualHash.ToLower() -ne $ExpectedHash.ToLower()) {
        Fail "checksum verification failed for $Asset — download may be corrupted or tampered. Try running this script again; if it fails again, do not run the downloaded binary and report this at https://github.com/SnapLogic/snaplogic-cli/issues"
    }

    Expand-Archive -Path $AssetPath -DestinationPath $TmpDir -Force

    $ExtractedExe = Join-Path $TmpDir "sl.exe"
    if (-not (Test-Path $ExtractedExe)) {
        Fail "sl.exe not found in $Asset after extraction — archive layout may have changed. Download and extract manually from $BaseUrl"
    }

    $InstallDir = if ($env:SL_INSTALL_DIR) { $env:SL_INSTALL_DIR } else { Join-Path $env:LOCALAPPDATA "sl\bin" }
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null

    $DestPath = Join-Path $InstallDir "sl.exe"
    Move-Item -Path $ExtractedExe -Destination $DestPath -Force

    Write-Host "Installed sl to $DestPath"

    $NormalizedInstallDir = $InstallDir.TrimEnd('\')
    $OnPath = @("User", "Machine") | ForEach-Object {
        [Environment]::GetEnvironmentVariable("Path", $_) -split ";" | ForEach-Object { $_.TrimEnd('\') }
    } | Where-Object { $_ -ieq $NormalizedInstallDir }

    if (-not $OnPath) {
        Write-Host "warning: $InstallDir is not on your PATH. Add it, e.g.:"
        Write-Host "  [Environment]::SetEnvironmentVariable('Path', `$env:Path + ';$InstallDir', 'User')"
    }

    & $DestPath --version
} finally {
    Remove-Item -Path $TmpDir -Recurse -Force -ErrorAction SilentlyContinue
}
