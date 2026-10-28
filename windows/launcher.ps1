<#
.SYNOPSIS
    DevBootstrapper WezTerm launcher: keeps the WezTerm nightly build current, then starts it.

.DESCRIPTION
    The Start-menu shortcut runs this script with a hidden window (docs/updates.md).
    At most once per day it checks the nightly release; when a newer build exists and no
    WezTerm from this folder is running, it downloads, verifies the published SHA-256,
    swaps the new build in and keeps the previous one for -Rollback.
    It always re-copies the DevBootstrapper stub config next to wezterm.exe before starting.

.PARAMETER UpdateOnly
    Update (or install) WezTerm without starting it.

.PARAMETER Force
    Check for a new build even if today's check already ran.

.PARAMETER Rollback
    Swap the previous build back in, then exit.

.PARAMETER ToolsDir
    The DevBootstrapper tools folder on Windows. Defaults to the parent of this script's folder.
#>
param(
    [switch]$UpdateOnly,
    [switch]$Force,
    [switch]$Rollback,
    [string]$ToolsDir = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2

$LauncherDir = Join-Path $ToolsDir 'launcher'
$WezDir = Join-Path $ToolsDir 'wezterm'
$PrevDir = Join-Path $ToolsDir 'wezterm.previous'
$StagingDir = Join-Path $ToolsDir 'wezterm.staging'
$StateFile = Join-Path $LauncherDir 'state.json'
$LogFile = Join-Path $LauncherDir 'launcher.log'
$ReleaseApi = 'https://api.github.com/repos/wezterm/wezterm/releases/tags/nightly'
$AssetName = 'WezTerm-windows-nightly.zip'

function Write-Log {
    param([string]$Message)
    $line = '{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Add-Content -Path $LogFile -Value $line
    Write-Verbose $line
}

function Initialize-Network {
    # TLS 1.2 for Windows PowerShell 5.1, and the system proxy with the user's Windows credentials.
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $proxy = [System.Net.WebRequest]::DefaultWebProxy
    if ($null -ne $proxy) {
        $proxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials
    }
}

function Get-LauncherState {
    $state = [pscustomobject]@{ lastCheck = ''; installed = '' }
    if (Test-Path $StateFile) {
        try {
            $saved = Get-Content -Path $StateFile -Raw | ConvertFrom-Json
            foreach ($name in 'lastCheck', 'installed') {
                if ($saved.PSObject.Properties.Name -contains $name) {
                    $state.$name = [string]$saved.$name
                }
            }
        }
        catch {
            Write-Log "ignoring unreadable state file: $_"
        }
    }
    return $state
}

function Save-LauncherState {
    param($State)
    $State | ConvertTo-Json | Set-Content -Path $StateFile -Encoding UTF8
}

function Get-NightlyAsset {
    $headers = @{ 'User-Agent' = 'DevBootstrapper-launcher' }
    $release = Invoke-RestMethod -Uri $ReleaseApi -Headers $headers -UseBasicParsing
    $zip = $release.assets | Where-Object { $_.name -eq $AssetName } | Select-Object -First 1
    if ($null -eq $zip) {
        throw "the nightly release has no $AssetName"
    }
    $sha = $release.assets | Where-Object { $_.name -eq "$AssetName.sha256" } | Select-Object -First 1
    $shaUrl = $null
    if ($null -ne $sha) {
        $shaUrl = $sha.browser_download_url
    }
    # The asset id changes whenever the nightly build is re-uploaded.
    return [pscustomobject]@{
        Url    = $zip.browser_download_url
        Stamp  = [string]$zip.id
        ShaUrl = $shaUrl
    }
}

function Test-WezTermRunning {
    $running = Get-Process -Name 'wezterm-gui', 'wezterm-mux-server', 'wezterm' -ErrorAction SilentlyContinue |
        Where-Object { $_.Path -and $_.Path.StartsWith($WezDir, [StringComparison]::OrdinalIgnoreCase) }
    return @($running).Count -gt 0
}

function Get-ExpectedHash {
    param([string]$Url)
    $content = (Invoke-WebRequest -Uri $Url -UseBasicParsing).Content
    if ($content -is [byte[]]) {
        $content = [Text.Encoding]::ASCII.GetString($content)
    }
    $match = [regex]::Match([string]$content, '[0-9a-fA-F]{64}')
    if (-not $match.Success) {
        throw "no SHA-256 found at $Url"
    }
    return $match.Value
}

function Install-Nightly {
    param($Asset)
    if (Test-Path $StagingDir) {
        Remove-Item -Path $StagingDir -Recurse -Force
    }
    New-Item -ItemType Directory -Path $StagingDir | Out-Null
    $zipPath = Join-Path $StagingDir $AssetName
    Write-Log "downloading $($Asset.Url)"
    Invoke-WebRequest -Uri $Asset.Url -OutFile $zipPath -UseBasicParsing

    if ($Asset.ShaUrl) {
        $expected = Get-ExpectedHash -Url $Asset.ShaUrl
        $actual = (Get-FileHash -Path $zipPath -Algorithm SHA256).Hash
        if ($actual -ne $expected) {
            throw "checksum mismatch for $AssetName (expected $expected, got $actual)"
        }
        Write-Log 'checksum verified'
    }
    else {
        Write-Log 'no published checksum; skipping verification'
    }

    $extractDir = Join-Path $StagingDir 'extract'
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [IO.Compression.ZipFile]::ExtractToDirectory($zipPath, $extractDir)
    $gui = Get-ChildItem -Path $extractDir -Recurse -Filter 'wezterm-gui.exe' | Select-Object -First 1
    if ($null -eq $gui) {
        throw 'the downloaded archive contains no wezterm-gui.exe'
    }

    if (Test-Path $PrevDir) {
        Remove-Item -Path $PrevDir -Recurse -Force
    }
    if (Test-Path $WezDir) {
        Move-Item -Path $WezDir -Destination $PrevDir
    }
    Move-Item -Path $gui.Directory.FullName -Destination $WezDir
    Remove-Item -Path $StagingDir -Recurse -Force
}

function Install-Stub {
    # The stub and the machine values written by install.ps1 live in the launcher folder,
    # so every swapped-in build gets them again.
    foreach ($pair in @(@('wezterm-stub.lua', 'wezterm.lua'), @('devboot-local.lua', 'devboot-local.lua'))) {
        $source = Join-Path $LauncherDir $pair[0]
        if ((Test-Path $source) -and (Test-Path $WezDir)) {
            Copy-Item -Path $source -Destination (Join-Path $WezDir $pair[1]) -Force
        }
    }
}

New-Item -ItemType Directory -Force -Path $LauncherDir | Out-Null
$gui = Join-Path $WezDir 'wezterm-gui.exe'

if ($Rollback) {
    if (-not (Test-Path $PrevDir)) {
        throw 'there is no previous WezTerm build to roll back to'
    }
    if (Test-WezTermRunning) {
        throw 'close WezTerm before rolling back'
    }
    $swap = Join-Path $ToolsDir 'wezterm.swap'
    Move-Item -Path $WezDir -Destination $swap
    Move-Item -Path $PrevDir -Destination $WezDir
    Move-Item -Path $swap -Destination $PrevDir
    Install-Stub
    Write-Log 'rolled back to the previous build'
    return
}

$state = Get-LauncherState
$today = Get-Date -Format 'yyyy-MM-dd'
$installed = Test-Path $gui

if ($Force -or -not $installed -or $state.lastCheck -ne $today) {
    try {
        Initialize-Network
        $asset = Get-NightlyAsset
        if (-not $installed -or $asset.Stamp -ne $state.installed) {
            if ($installed -and (Test-WezTermRunning)) {
                # Leave lastCheck unset so the next start tries again.
                Write-Log 'a newer nightly exists; deferred because WezTerm is running'
            }
            else {
                Install-Nightly -Asset $asset
                $state.installed = $asset.Stamp
                $state.lastCheck = $today
                Write-Log "installed nightly build (asset $($asset.Stamp))"
            }
        }
        else {
            $state.lastCheck = $today
        }
        Save-LauncherState -State $state
    }
    catch {
        Write-Log "update failed: $_"
        if (-not (Test-Path $gui)) {
            throw
        }
    }
}

Install-Stub

if (-not $UpdateOnly) {
    Start-Process -FilePath $gui -WorkingDirectory $env:USERPROFILE
}
