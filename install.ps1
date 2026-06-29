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
$ProfileHome = Join-Path $HermesRoot 'profiles\agentrouter'
$QwenVersion = '0.19.3'

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
$CliFound = [bool]$CliPath

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
    & $Npm install -g "@qwen-code/qwen-code@$QwenVersion"
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
        try {
            $result = & $Qwen --bare --auth-type openai --model $Model --approval-mode plan --output-format json --max-session-turns 1 --max-tool-calls 0 'Reply exactly AGENTROUTER_GLM52_OK' 2>&1 | Out-String
            if ($LASTEXITCODE -ne 0 -or $result -notmatch 'AGENTROUTER_GLM52_OK') { throw 'AgentRouter validation failed. Verify the token and try again.' }
        } finally {
            $env:OPENAI_API_KEY=$old[0]; $env:OPENAI_BASE_URL=$old[1]; $env:OPENAI_MODEL=$old[2]; $env:PATH=$old[3]
        }
    }

    New-Item -ItemType Directory -Path $InstallRoot -Force | Out-Null
    $EncryptedToken = $Token | ConvertTo-SecureString -AsPlainText -Force | ConvertFrom-SecureString
    [IO.File]::WriteAllText((Join-Path $InstallRoot 'token.dpapi'), $EncryptedToken, [Text.UTF8Encoding]::new($false))
    $EncryptedToken = $null

    $ConfigCli = if ($CliPath) { $CliPath } else { $BundledCli }
    if (-not (Test-Path -LiteralPath $ProfileHome)) {
        & $ConfigCli profile create agentrouter --clone --no-alias --description 'Hermes with AgentRouter, pinned to GLM-5.2.'
        if ($LASTEXITCODE -ne 0) { throw 'Could not create the isolated AgentRouter profile.' }
    }
    $PatchPython = Resolve-Executable @((Join-Path $HermesRoot 'hermes-agent\venv\Scripts\python.exe'),'python')
    if (-not $PatchPython) { throw 'Python is required to install the Hermes compatibility patch.' }
    & $PatchPython (Join-Path $PSScriptRoot 'scripts\patch-hermes.py') --hermes-root (Join-Path $HermesRoot 'hermes-agent')
    if ($LASTEXITCODE -ne 0) { throw 'Hermes compatibility patch failed; all source changes were rolled back.' }
    & $ConfigCli -p agentrouter config set model.default $Model
    if ($LASTEXITCODE -ne 0) { throw 'Could not set the Hermes default model.' }
    & $ConfigCli -p agentrouter config set model.provider copilot-acp
    if ($LASTEXITCODE -ne 0) { throw 'Could not set the Hermes provider.' }
    & $ConfigCli -p agentrouter config set model.base_url 'acp://copilot'
    if ($LASTEXITCODE -ne 0) { throw 'Could not set the Hermes ACP endpoint.' }
    & $ConfigCli -p agentrouter config set agent.reasoning_effort medium
    & $ConfigCli -p agentrouter config set agent.max_turns 20
    & $ConfigCli -p agentrouter config set display.show_reasoning true

    $Node = Resolve-Executable @((Join-Path $BundledNode 'node.exe'),'node')
    $QwenRoot = Join-Path (Split-Path $Qwen) 'node_modules\@qwen-code\qwen-code'
    if (-not (Test-Path -LiteralPath $QwenRoot)) { throw 'The Qwen Code provider runtime could not be located.' }
    $settings = @{ target=$Target; desktopExe=$DesktopExe; hermesCli=$CliPath; qwenCommand=$Qwen; nodeCommand=$Node; qwenRoot=$QwenRoot; qwenVersion=$QwenVersion; profileHome=$ProfileHome; model=$Model; baseUrl=$BaseUrl }
    $settings | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $InstallRoot 'settings.json') -Encoding UTF8
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'scripts\runtime-windows.ps1') -Destination (Join-Path $InstallRoot 'runtime.ps1') -Force
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'scripts\qwen-provider-bridge.mjs') -Destination (Join-Path $InstallRoot 'qwen-provider-bridge.mjs') -Force
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'scripts\uninstall.ps1') -Destination (Join-Path $InstallRoot 'uninstall.ps1') -Force

    if ($Target -in @('Desktop','Both')) {
        $running = Get-Process -Name Hermes -ErrorAction SilentlyContinue
        if ($running) {
            Write-Host 'Hermes Desktop must be closed once to update its saved model selection.' -ForegroundColor Yellow
            Read-Host 'Close Hermes completely, then press Enter'
            if (Get-Process -Name Hermes -ErrorAction SilentlyContinue) { throw 'Hermes is still running.' }
        }
        # The dedicated HERMES_HOME profile keeps Desktop state isolated; the
        # normal Hermes application and its ChatGPT provider remain untouched.
    }

    $cmd='@echo off' + "`r`n" + 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%LOCALAPPDATA%\hermes-agentrouter\runtime.ps1" %*'
    [IO.File]::WriteAllText((Join-Path $InstallRoot 'hermes-agentrouter.cmd'),$cmd,[Text.UTF8Encoding]::new($false))
    $userPath=[Environment]::GetEnvironmentVariable('Path','User')
    if (($userPath -split ';') -notcontains $InstallRoot) { [Environment]::SetEnvironmentVariable('Path',(($userPath.TrimEnd(';')+';'+$InstallRoot).Trim(';')),'User') }

    if ($Target -in @('Desktop','Both')) {
        $desktop=[Environment]::GetFolderPath('Desktop')
        $shortcut=(New-Object -ComObject WScript.Shell).CreateShortcut((Join-Path $desktop 'Hermes - AgentRouter.lnk'))
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
