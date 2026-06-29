[CmdletBinding()]
param(
    [ValidateSet('Auto','Desktop','CLI','Both')][string]$Target = 'Auto',
    [string]$TokenFile,
    [switch]$SkipTest
)

$ErrorActionPreference = 'Stop'
$Model = 'glm-5.2'
$BaseUrl = 'https://agentrouter.org/v1'
$InstallRoot = Join-Path $env:LOCALAPPDATA 'hermes-agentrouter'
$HermesRoot = Join-Path $env:LOCALAPPDATA 'hermes'
$DesktopExe = Join-Path $HermesRoot 'hermes-agent\apps\desktop\release\win-unpacked\Hermes.exe'
$BundledCli = Join-Path $HermesRoot 'hermes-agent\venv\Scripts\hermes.exe'
$BundledNode = Join-Path $HermesRoot 'node'

function Resolve-Executable([string[]]$Names) {
    foreach ($name in $Names) {
        if (-not $name) { continue }
        $cmd = Get-Command $name -ErrorAction SilentlyContinue
        if ($cmd) { return $cmd.Source }
        if (Test-Path -LiteralPath $name) { return (Resolve-Path -LiteralPath $name).Path }
    }
    return $null
}

$DesktopFound = Test-Path -LiteralPath $DesktopExe
$PathCli = Resolve-Executable @('hermes')
$CliPath = if ($PathCli) { $PathCli } elseif (Test-Path -LiteralPath $BundledCli) { $BundledCli } else { $null }
$CliFound = [bool]$PathCli

if (-not $DesktopFound -and -not $CliPath) {
    throw 'Hermes was not found. Install Hermes Desktop or Hermes CLI first.'
}

if ($Target -eq 'Auto') {
    if ($DesktopFound -and $CliFound) {
        $choices = [System.Management.Automation.Host.ChoiceDescription[]]@(
            (New-Object System.Management.Automation.Host.ChoiceDescription '&Both','Configure Desktop and CLI'),
            (New-Object System.Management.Automation.Host.ChoiceDescription '&Desktop','Configure Desktop only'),
            (New-Object System.Management.Automation.Host.ChoiceDescription '&CLI','Configure CLI only')
        )
        $selection = $Host.UI.PromptForChoice('Hermes targets','Both Hermes Desktop and CLI were detected.', $choices, 0)
        $Target = @('Both','Desktop','CLI')[$selection]
    } elseif ($DesktopFound) { $Target = 'Desktop' } else { $Target = 'CLI' }
}

if ($Target -in @('Desktop','Both') -and -not $DesktopFound) { throw 'Hermes Desktop was selected but not found.' }
if ($Target -in @('CLI','Both') -and -not $CliPath) { throw 'Hermes CLI was selected but not found.' }

$Node = Resolve-Executable @((Join-Path $BundledNode 'node.exe'),'node')
$Npm = Resolve-Executable @((Join-Path $BundledNode 'npm.cmd'),'npm')
$Qwen = Resolve-Executable @((Join-Path $BundledNode 'qwen.cmd'),'qwen')
if (-not $Qwen) {
    if (-not $Npm) { throw 'Node.js/npm is required to install Qwen Code.' }
    if ($Node) { $env:PATH = "$(Split-Path $Node);$env:PATH" }
    Write-Host 'Installing Qwen Code...'
    & $Npm install -g '@qwen-code/qwen-code'
    if ($LASTEXITCODE -ne 0) { throw 'Qwen Code installation failed.' }
    $Qwen = Resolve-Executable @((Join-Path $BundledNode 'qwen.cmd'),'qwen')
}
if (-not $Qwen) { throw 'Qwen Code could not be located after installation.' }

$SecureToken = if ($TokenFile) {
    if (-not (Test-Path -LiteralPath $TokenFile)) { throw "Token file was not found: $TokenFile" }
    ConvertTo-SecureString ([IO.File]::ReadAllText($TokenFile).Trim()) -AsPlainText -Force
} else {
    Read-Host 'AgentRouter API token' -AsSecureString
}
$ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureToken)
try {
    $Token = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
    if ([string]::IsNullOrWhiteSpace($Token)) { throw 'The API token is empty.' }

    if (-not $SkipTest) {
        Write-Host "Testing AgentRouter with $Model..."
        $old = @($env:OPENAI_API_KEY,$env:OPENAI_BASE_URL,$env:OPENAI_MODEL,$env:PATH)
        $env:OPENAI_API_KEY = $Token; $env:OPENAI_BASE_URL = $BaseUrl; $env:OPENAI_MODEL = $Model
        $env:PATH = "$(Split-Path $Qwen);$env:PATH"
        $result = & $Qwen --bare --auth-type openai --model $Model --approval-mode plan --output-format json --max-session-turns 1 --max-tool-calls 0 'Reply exactly AGENTROUTER_GLM52_OK' 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0 -or $result -notmatch 'AGENTROUTER_GLM52_OK') { throw "AgentRouter validation failed.`n$result" }
        $env:OPENAI_API_KEY=$old[0]; $env:OPENAI_BASE_URL=$old[1]; $env:OPENAI_MODEL=$old[2]; $env:PATH=$old[3]
    }

    New-Item -ItemType Directory -Path $InstallRoot -Force | Out-Null
    $EncryptedToken = $Token | ConvertTo-SecureString -AsPlainText -Force | ConvertFrom-SecureString
    [IO.File]::WriteAllText((Join-Path $InstallRoot 'token.dpapi'), $EncryptedToken, [Text.UTF8Encoding]::new($false))
    $EncryptedToken = $null

    $ConfigPath = Join-Path $HermesRoot 'config.yaml'
    if (Test-Path -LiteralPath $ConfigPath) {
        $Backup = Join-Path $InstallRoot 'config.before-agentrouter.yaml'
        if (-not (Test-Path -LiteralPath $Backup)) { Copy-Item -LiteralPath $ConfigPath -Destination $Backup }
    }

    $ConfigCli = if ($CliPath) { $CliPath } else { $BundledCli }
    & $ConfigCli config set model.default $Model
    & $ConfigCli config set model.provider copilot-acp
    & $ConfigCli config set model.base_url 'acp://copilot'

    $settings = @{ target=$Target; desktopExe=$DesktopExe; hermesCli=$CliPath; qwenCommand=$Qwen; model=$Model; baseUrl=$BaseUrl }
    $settings | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $InstallRoot 'settings.json') -Encoding UTF8
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'scripts\runtime-windows.ps1') -Destination (Join-Path $InstallRoot 'runtime.ps1') -Force
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'scripts\uninstall.ps1') -Destination (Join-Path $InstallRoot 'uninstall.ps1') -Force

    if ($Target -in @('Desktop','Both')) {
        $running = Get-Process -Name Hermes -ErrorAction SilentlyContinue
        if ($running) {
            Write-Host 'Hermes Desktop must be closed once to update its saved model selection.' -ForegroundColor Yellow
            Read-Host 'Close Hermes completely, then press Enter'
            if (Get-Process -Name Hermes -ErrorAction SilentlyContinue) { throw 'Hermes is still running.' }
        }
        $LevelDb = Join-Path $env:APPDATA 'Hermes\Local Storage\leveldb'
        if (Test-Path -LiteralPath $LevelDb) {
            if (-not $Npm -or -not $Node) { throw 'Node.js/npm is required to update Hermes Desktop model state.' }
            $UiTools = Join-Path $InstallRoot 'ui-tools'
            New-Item -ItemType Directory -Path $UiTools -Force | Out-Null
            Copy-Item (Join-Path $PSScriptRoot 'scripts\update-ui-state.cjs') (Join-Path $UiTools 'update-ui-state.cjs') -Force
            $UiBackup = Join-Path $InstallRoot 'desktop-leveldb.before-agentrouter'
            if (-not (Test-Path $UiBackup)) { Copy-Item -LiteralPath $LevelDb -Destination $UiBackup -Recurse }
            $env:PATH = "$(Split-Path $Node);$env:PATH"
            & $Npm install --prefix $UiTools classic-level --no-audit --no-fund | Out-Null
            & $Node (Join-Path $UiTools 'update-ui-state.cjs') $LevelDb
            if ($LASTEXITCODE -ne 0) { throw 'Hermes Desktop model-state update failed.' }
        }
    }

    $cmd='@echo off' + "`r`n" + 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%LOCALAPPDATA%\hermes-agentrouter\runtime.ps1" %*'
    [IO.File]::WriteAllText((Join-Path $InstallRoot 'hermes-agentrouter.cmd'),$cmd,[Text.UTF8Encoding]::new($false))
    $userPath=[Environment]::GetEnvironmentVariable('Path','User')
    if (($userPath -split ';') -notcontains $InstallRoot) { [Environment]::SetEnvironmentVariable('Path',(($userPath.TrimEnd(';')+';'+$InstallRoot).Trim(';')),'User') }

    if ($Target -in @('Desktop','Both')) {
        $desktop=[Environment]::GetFolderPath('Desktop')
        $shortcut=(New-Object -ComObject WScript.Shell).CreateShortcut((Join-Path $desktop 'Hermes - AgentRouter GLM 5.2.lnk'))
        $shortcut.TargetPath=(Get-Command powershell.exe).Source
        $shortcut.Arguments='-NoProfile -ExecutionPolicy Bypass -File "'+(Join-Path $InstallRoot 'runtime.ps1')+'" --desktop'
        $shortcut.WorkingDirectory=$InstallRoot; $shortcut.IconLocation="$DesktopExe,0"; $shortcut.Save()
    }
    Write-Host "Installed successfully for: $Target" -ForegroundColor Green
    Write-Host 'CLI command: hermes-agentrouter'
} finally {
    if ($ptr -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
    $Token=$null; $env:OPENAI_API_KEY=$null
}
