<#
.SYNOPSIS
    DevBootstrapper one-time Windows installer (docs/getting-started.md).

.DESCRIPTION
    Run from any PowerShell window:

        irm https://raw.githubusercontent.com/YThibos/DevBootstrapper/main/windows/install.ps1 | iex

    With parameters, for example to install from another branch:

        & ([scriptblock]::Create((irm https://raw.githubusercontent.com/YThibos/DevBootstrapper/main/windows/install.ps1))) -Branch my-branch

    It checks WSL2 and Ubuntu (and explains how to install them if missing), optionally tunes
    .wslconfig, installs WezTerm nightly and its launcher under C:\development\tools, creates a
    Start-menu shortcut, clones the dev home into ~/development inside WSL and runs the first
    devup there. It needs no administrator rights.

.PARAMETER Distro
    The WSL distribution to use. By default the installed Ubuntu distribution (asks if several).

.PARAMETER Branch
    The DevBootstrapper branch to install from.

.PARAMETER RepoUrl
    The DevBootstrapper repository.

.PARAMETER ToolsDir
    The Windows-side tools folder.

.PARAMETER WslConfig
    ask (default), yes or no: whether to tune %USERPROFILE%\.wslconfig.
#>
param(
    [string]$Distro = '',
    [string]$Branch = 'main',
    [string]$RepoUrl = 'https://github.com/YThibos/DevBootstrapper.git',
    [string]$ToolsDir = 'C:\development\tools',
    [ValidateSet('ask', 'yes', 'no')]
    [string]$WslConfig = 'ask'
)

function Write-Step {
    # A banner per part of the installation, set apart by blank lines (same style as devup).
    param([string]$Text)
    $line = '=' * 64
    Write-Host "`n`n$line`n  $Text`n$line`n" -ForegroundColor Cyan
}
function Write-Info { param([string]$Text) Write-Host "   $Text" }
function Write-Warn { param([string]$Text) Write-Host "   warning: $Text" -ForegroundColor Yellow }

function Initialize-Network {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $proxy = [System.Net.WebRequest]::DefaultWebProxy
    if ($null -ne $proxy) {
        $proxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials
    }
}

function Invoke-Wsl {
    # Runs wsl.exe with UTF-8 output and returns trimmed, non-empty lines.
    param([string[]]$Arguments)
    $env:WSL_UTF8 = '1'
    $output = & wsl.exe @Arguments 2>$null
    return @($output | ForEach-Object { ($_ -replace "`0", '').Trim() } | Where-Object { $_ })
}

function Show-WslHelp {
    param([bool]$WslPresent)
    Write-Step 'WSL2 with Ubuntu is required first'
    $newest = 'Ubuntu'
    if ($WslPresent) {
        $online = Invoke-Wsl @('--list', '--online')
        $ubuntu = $online | ForEach-Object { if ($_ -match '^(Ubuntu-(\d+)\.(\d+))\s') { [pscustomobject]@{ Name = $Matches[1]; Major = [int]$Matches[2]; Minor = [int]$Matches[3] } } } |
            Sort-Object -Property Major, Minor -Descending | Select-Object -First 1
        if ($null -ne $ubuntu) {
            $newest = $ubuntu.Name
        }
    }
    Write-Info 'Open PowerShell as administrator and run:'
    Write-Host ''
    Write-Host "    wsl --install -d $newest" -ForegroundColor Green
    Write-Host ''
    Write-Info 'Restart Windows if asked, open Ubuntu once from the Start menu to create your Linux user,'
    Write-Info 'then run this installer again.'
}

function Select-Distro {
    param([string]$Requested)
    if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
        Show-WslHelp -WslPresent $false
        return $null
    }
    $installed = Invoke-Wsl @('--list', '--quiet')
    if ($Requested) {
        if ($installed -notcontains $Requested) {
            throw "WSL distribution '$Requested' is not installed (installed: $($installed -join ', '))"
        }
        $choice = $Requested
    }
    else {
        $ubuntu = @($installed | Where-Object { $_ -like 'Ubuntu*' })
        if ($ubuntu.Count -eq 0) {
            Show-WslHelp -WslPresent $true
            return $null
        }
        $choice = $ubuntu[0]
        if ($ubuntu.Count -gt 1) {
            Write-Info 'Several Ubuntu distributions are installed:'
            for ($i = 0; $i -lt $ubuntu.Count; $i++) {
                Write-Info "  [$i] $($ubuntu[$i])"
            }
            $index = Read-Host '   Which one? [0]'
            if ($index -match '^\d+$' -and [int]$index -lt $ubuntu.Count) {
                $choice = $ubuntu[[int]$index]
            }
        }
    }
    $verbose = Invoke-Wsl @('--list', '--verbose')
    foreach ($line in $verbose) {
        $parts = ($line -replace '^\*', '').Trim() -split '\s+'
        if ($parts.Count -ge 3 -and $parts[0] -eq $choice -and $parts[-1] -eq '1') {
            Write-Warn "$choice runs on WSL 1. Convert it with: wsl --set-version $choice 2"
            return $null
        }
    }
    return $choice
}

function Set-IniValue {
    # Sets key=value inside [section] of an INI-style line list and returns the new list.
    param([string[]]$Lines, [string]$Section, [string]$Key, [string]$Value)
    $result = New-Object System.Collections.Generic.List[string]
    $inSection = $false
    $sectionSeen = $false
    $done = $false
    foreach ($line in $Lines) {
        if ($line -match '^\s*\[(.+)\]\s*$') {
            if ($inSection -and -not $done) {
                $result.Add("$Key=$Value")
                $done = $true
            }
            $inSection = ($Matches[1] -eq $Section)
            if ($inSection) { $sectionSeen = $true }
        }
        elseif ($inSection -and $line -match "^\s*$([regex]::Escape($Key))\s*=") {
            if (-not $done) {
                $result.Add("$Key=$Value")
                $done = $true
            }
            continue
        }
        $result.Add($line)
    }
    if (-not $done) {
        if (-not $sectionSeen) {
            $result.Add("[$Section]")
        }
        $result.Add("$Key=$Value")
    }
    return , $result.ToArray()
}

function Update-WslConfig {
    param([string]$Mode)
    if ($Mode -eq 'no') {
        return $false
    }
    $path = Join-Path $env:USERPROFILE '.wslconfig'
    if ($Mode -eq 'ask') {
        Write-Info 'Optional: tune .wslconfig for mirrored networking (helps on VPNs and proxies),'
        Write-Info 'DNS tunnelling, the Windows proxy inside WSL, and a memory cap of half your RAM.'
        $answer = Read-Host '   Apply these .wslconfig settings? [y/N]'
        if ($answer -notmatch '^[Yy]') {
            return $false
        }
    }
    $lines = @()
    if (Test-Path $path) {
        $lines = @(Get-Content -Path $path)
        Copy-Item -Path $path -Destination "$path.devboot-backup-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    }
    $memoryGb = [math]::Max(4, [math]::Floor((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB / 2))
    $settings = [ordered]@{ networkingMode = 'mirrored'; dnsTunneling = 'true'; autoProxy = 'true'; memory = "${memoryGb}GB" }
    foreach ($key in $settings.Keys) {
        $lines = Set-IniValue -Lines $lines -Section 'wsl2' -Key $key -Value $settings[$key]
    }
    Set-Content -Path $path -Value $lines -Encoding ASCII
    Write-Info "updated $path"
    return $true
}

function Get-RawFile {
    param([string]$RelativePath, [string]$Destination)
    $base = $RepoUrl -replace '^https://github.com/', 'https://raw.githubusercontent.com/' -replace '\.git$', ''
    Invoke-WebRequest -Uri "$base/$Branch/$RelativePath" -OutFile $Destination -UseBasicParsing
}

function Get-SystemProxy {
    try {
        $target = [Uri]'https://github.com'
        $proxy = [System.Net.WebRequest]::GetSystemWebProxy().GetProxy($target)
        if ($proxy.Host -ne $target.Host) {
            return $proxy.AbsoluteUri.TrimEnd('/')
        }
    }
    catch {
        Write-Warn "could not read the Windows proxy settings: $_"
    }
    return ''
}

function New-Shortcut {
    param([string]$Launcher, [string]$Icon)
    $programs = [Environment]::GetFolderPath('Programs')
    $path = Join-Path $programs 'WezTerm (DevBootstrapper).lnk'
    $shell = New-Object -ComObject WScript.Shell
    $link = $shell.CreateShortcut($path)
    $link.TargetPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $link.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$Launcher`""
    $link.WorkingDirectory = $env:USERPROFILE
    $link.IconLocation = "$Icon,0"
    $link.WindowStyle = 7
    $link.Save()
    Write-Info "Start-menu shortcut: $path"
}

function Install-DevBootstrapper {
    # Scoped to this function so a piped "irm | iex" run leaves the caller's session as it was.
    $ErrorActionPreference = 'Stop'
    Set-StrictMode -Version 2
    Initialize-Network

    Write-Step 'Checking WSL2 and Ubuntu'
    $selected = Select-Distro -Requested $Distro
    if (-not $selected) {
        return
    }
    Write-Info "using WSL distribution $selected"

    $linuxHome = (Invoke-Wsl @('-d', $selected, '-e', 'sh', '-c', 'echo $HOME')) -join ''
    if (-not $linuxHome) {
        throw "could not read the Linux home folder of $selected"
    }
    $devHome = "$linuxHome/development"
    $uncRoot = "\\wsl.localhost\$selected"
    if (-not (Test-Path "$uncRoot\")) {
        $uncRoot = "\\wsl$\$selected"
    }
    $devHomeUnc = $uncRoot + ($devHome -replace '/', '\')

    Write-Step '.wslconfig (optional)'
    $wslConfigChanged = Update-WslConfig -Mode $WslConfig

    Write-Step "WezTerm nightly and launcher in $ToolsDir"
    $launcherDir = Join-Path $ToolsDir 'launcher'
    New-Item -ItemType Directory -Force -Path $launcherDir | Out-Null
    $launcher = Join-Path $launcherDir 'launcher.ps1'
    Get-RawFile -RelativePath 'windows/launcher.ps1' -Destination $launcher
    Get-RawFile -RelativePath 'windows/wezterm-stub.lua' -Destination (Join-Path $launcherDir 'wezterm-stub.lua')
    $local = @(
        '-- Machine values for the DevBootstrapper WezTerm stub, written by install.ps1.',
        'return {',
        "  distro = '$selected',",
        "  dev_home = '$devHome',",
        "  dev_home_unc = [[$devHomeUnc]],",
        "  config_path = [[$devHomeUnc\config\wezterm\wezterm.lua]],",
        '}'
    )
    Set-Content -Path (Join-Path $launcherDir 'devboot-local.lua') -Value $local -Encoding ASCII
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $launcher -UpdateOnly -ToolsDir $ToolsDir
    if ($LASTEXITCODE -ne 0) {
        throw "the WezTerm download failed; see $launcherDir\launcher.log"
    }
    New-Shortcut -Launcher $launcher -Icon (Join-Path $ToolsDir 'wezterm\wezterm-gui.exe')

    Write-Step "Dev home in WSL ($devHome)"
    $proxy = Get-SystemProxy
    if ($proxy) {
        Write-Info "Windows uses the proxy $proxy for GitHub; passing it to the first setup."
    }
    $script = @'
set -e
if [ -d "$HOME/development/.git" ]; then
  echo "   ~/development already exists; keeping it"
elif [ -e "$HOME/development" ] && [ -n "$(ls -A "$HOME/development" 2>/dev/null)" ]; then
  echo "error: ~/development exists, is not empty and is not a DevBootstrapper clone" >&2
  exit 3
else
  if ! command -v git >/dev/null 2>&1; then
    echo "error: git is missing. Run: sudo apt-get update && sudo apt-get install -y git" >&2
    exit 4
  fi
  if [ -n "${DEVBOOT_DETECTED_PROXY:-}" ]; then
    export https_proxy="$DEVBOOT_DETECTED_PROXY" http_proxy="$DEVBOOT_DETECTED_PROXY"
  fi
  git clone --branch "$DEVBOOT_BRANCH" "$DEVBOOT_REPO" "$HOME/development"
fi
exec bash "$HOME/development/install/devup.sh" --first-run
'@
    $scriptPath = "$uncRoot\tmp\devboot-first-run.sh"
    [IO.File]::WriteAllText($scriptPath, ($script -replace "`r`n", "`n"))
    $env:DEVBOOT_DETECTED_PROXY = $proxy
    $env:DEVBOOT_BRANCH = $Branch
    $env:DEVBOOT_REPO = $RepoUrl
    $shared = 'DEVBOOT_DETECTED_PROXY/u:DEVBOOT_BRANCH/u:DEVBOOT_REPO/u'
    if ($env:WSLENV) {
        $env:WSLENV = "$($env:WSLENV):$shared"
    }
    else {
        $env:WSLENV = $shared
    }
    & wsl.exe -d $selected --cd '~' -- bash /tmp/devboot-first-run.sh
    $firstRunExit = $LASTEXITCODE
    if ($firstRunExit -ne 0) {
        Write-Warn "the first setup inside WSL ended with exit code $firstRunExit; fix the reported problem and run devup in WezTerm"
    }

    if (Test-Path "$devHomeUnc\tools\state\needs-wsl-restart") {
        Write-Step "Restarting $selected so /etc/wsl.conf takes effect"
        Remove-Item -Path "$devHomeUnc\tools\state\needs-wsl-restart" -Force
        & wsl.exe --terminate $selected | Out-Null
    }
    if ($wslConfigChanged) {
        Write-Info '.wslconfig changes need a full WSL restart, which also restarts Docker Desktop''s WSL engine.'
        $answer = Read-Host '   Run "wsl --shutdown" now? [y/N]'
        if ($answer -match '^[Yy]') {
            & wsl.exe --shutdown | Out-Null
        }
        else {
            Write-Info 'Run "wsl --shutdown" later to apply them.'
        }
    }

    Write-Step 'Starting WezTerm'
    Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') `
        -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', "`"$launcher`"") `
        -WindowStyle Hidden
    Write-Info 'Done. Next time, start "WezTerm (DevBootstrapper)" from the Start menu.'
}

Install-DevBootstrapper
