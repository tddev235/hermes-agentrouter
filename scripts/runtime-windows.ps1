param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Arguments)
$ErrorActionPreference='Stop'
$root=Join-Path $env:LOCALAPPDATA 'hermes-agentrouter'
$s=Get-Content -Raw (Join-Path $root 'settings.json') | ConvertFrom-Json
$env:HERMES_PROFILE='agentrouter'
$env:HERMES_AGENTROUTER_TOKEN_EFFICIENT='1'

function Set-AgentRouterKey {
  param([string[]]$KeyArguments)
  $tokenFile=$null
  if($KeyArguments.Count -ge 2 -and $KeyArguments[0] -eq '--token-file'){$tokenFile=$KeyArguments[1]}
  $newSecure=if($tokenFile){
    if(-not (Test-Path -LiteralPath $tokenFile)){throw "Token file was not found: $tokenFile"}
    ConvertTo-SecureString ([IO.File]::ReadAllText($tokenFile).Trim()) -AsPlainText -Force
  }else{Read-Host 'New AgentRouter API token' -AsSecureString}
  $newPtr=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($newSecure)
  try{
    $newToken=[Runtime.InteropServices.Marshal]::PtrToStringBSTR($newPtr)
    if([string]::IsNullOrWhiteSpace($newToken)){throw 'The API token is empty.'}
    $old=@($env:OPENAI_API_KEY,$env:OPENAI_BASE_URL,$env:OPENAI_MODEL,$env:QWEN_CODE_ROOT,$env:QWEN_CODE_VERSION)
    $env:OPENAI_API_KEY=$newToken; $env:OPENAI_BASE_URL=$s.baseUrl; $env:OPENAI_MODEL=$s.model
    $env:QWEN_CODE_ROOT=$s.qwenRoot; $env:QWEN_CODE_VERSION=$s.qwenVersion
    $check=& $s.nodeCommand (Join-Path $root 'qwen-provider-bridge.mjs') --check 2>&1 | Out-String
    if($LASTEXITCODE -ne 0 -or $check -notmatch 'AGENTROUTER_GLM52_OK'){throw 'The new key was rejected by AgentRouter; the existing key was kept.'}
    $next=Join-Path $root 'token.dpapi.new'
    [IO.File]::WriteAllText($next,(ConvertFrom-SecureString $newSecure),[Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $next -Destination (Join-Path $root 'token.dpapi') -Force
    $task=Get-ScheduledTask -TaskName 'Hermes AgentRouter Gateway' -ErrorAction SilentlyContinue
    if($task){
      Stop-ScheduledTask -TaskName $task.TaskName -ErrorAction SilentlyContinue
      Get-CimInstance Win32_Process | Where-Object {$_.CommandLine -match 'hermes(.exe)?"?\s+-p\s+agentrouter\s+gateway\s+run'} | ForEach-Object {Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue}
      Start-Sleep -Seconds 1; Start-ScheduledTask -TaskName $task.TaskName
    }
    Write-Host 'AgentRouter key updated, validated, and activated.' -ForegroundColor Green
  }finally{
    $newToken=$null
    if($newPtr -ne [IntPtr]::Zero){[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($newPtr)}
    $env:OPENAI_API_KEY=$old[0]; $env:OPENAI_BASE_URL=$old[1]; $env:OPENAI_MODEL=$old[2]
    $env:QWEN_CODE_ROOT=$old[3]; $env:QWEN_CODE_VERSION=$old[4]
  }
}

if($Arguments.Count -gt 0 -and $Arguments[0] -eq 'key'){
  if($Arguments.Count -lt 2 -or $Arguments[1] -ne 'set'){throw 'Usage: hermes-agentrouter key set [--token-file PATH]'}
  [string[]]$keyArgs=if($Arguments.Count -gt 2){@($Arguments[2..($Arguments.Count-1)])}else{@()}
  Set-AgentRouterKey $keyArgs
  exit 0
}
$encoded=(Get-Content -Raw (Join-Path $root 'token.dpapi')).TrimStart([char]0xFEFF).Trim()
$secure=$encoded | ConvertTo-SecureString
$ptr=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
try {
  $token=[Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
  $env:OPENAI_API_KEY=$token; $env:OPENAI_BASE_URL=$s.baseUrl; $env:OPENAI_MODEL=$s.model
  $env:HERMES_COPILOT_ACP_COMMAND=$s.qwenCommand
  $env:HERMES_COPILOT_ACP_ARGS='--acp --bare --auth-type openai --model {model}'
  $env:HERMES_AGENTROUTER_RAW_BRIDGE=(Join-Path $root 'qwen-provider-bridge.mjs')
  $env:HERMES_AGENTROUTER_NODE=$s.nodeCommand
  $env:QWEN_CODE_ROOT=$s.qwenRoot
  $env:QWEN_CODE_VERSION=$s.qwenVersion
  $env:PYTHONUTF8='1'; $env:PATH="$(Split-Path $s.qwenCommand);$env:PATH"
  if ($Arguments -contains '--check') {
    & $s.nodeCommand (Join-Path $root 'qwen-provider-bridge.mjs') --check
  } elseif ($Arguments -contains '--desktop') {
    if (Get-Process -Name Hermes -ErrorAction SilentlyContinue) { throw 'Close Hermes completely before using the AgentRouter shortcut.' }
    $env:HERMES_HOME=$s.hermesRoot
    $env:HERMES_DESKTOP_USER_DATA_DIR=(Join-Path $root 'desktop-data')
    New-Item -ItemType Directory -Path $env:HERMES_DESKTOP_USER_DATA_DIR -Force | Out-Null
    $profileJson=@{profile='agentrouter'} | ConvertTo-Json
    [IO.File]::WriteAllText((Join-Path $env:HERMES_DESKTOP_USER_DATA_DIR 'active-profile.json'),$profileJson,[Text.UTF8Encoding]::new($false))
    Start-Process -FilePath $s.desktopExe -WorkingDirectory (Split-Path $s.desktopExe)
  } else {
    if ($Arguments.Count -gt 0 -and $Arguments[0] -eq 'gateway') {
      $env:HERMES_HOME=$s.hermesRoot
      [string[]]$gatewayArgs = if ($Arguments.Count -gt 1) { @($Arguments[1..($Arguments.Count-1)]) } else { @() }
      if($gatewayArgs.Count -gt 0 -and $gatewayArgs[0] -eq 'install-service'){
        $taskName='Hermes AgentRouter Gateway'
        $runtime=Join-Path $root 'runtime.ps1'
        $action=New-ScheduledTaskAction -Execute 'powershell.exe' -Argument ('-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "'+$runtime+'" gateway supervise') -WorkingDirectory $env:USERPROFILE
        $trigger=New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
        $taskSettings=New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) -MultipleInstances IgnoreNew
        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $taskSettings -Description 'Supervised Hermes AgentRouter messaging gateway.' -Force | Out-Null
        Start-ScheduledTask -TaskName $taskName
        Write-Host 'Gateway service installed and started.' -ForegroundColor Green
      }elseif($gatewayArgs.Count -gt 0 -and $gatewayArgs[0] -eq 'supervise'){
        while($true){
          & $s.hermesCli -p agentrouter gateway run
          $exitCode=$LASTEXITCODE
          Write-Warning "Gateway exited with code $exitCode; restarting in 5 seconds."
          Start-Sleep -Seconds 5
        }
      }else{
        & $s.hermesCli -p agentrouter gateway @gatewayArgs
      }
    } else {
      $env:HERMES_HOME=$s.profileHome
      & $s.hermesCli chat --provider copilot-acp --model 'glm-5.2' @Arguments
    }
  }
} finally {
  if($ptr -ne [IntPtr]::Zero){[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)}
  $token=$null; $env:OPENAI_API_KEY=$null
}
