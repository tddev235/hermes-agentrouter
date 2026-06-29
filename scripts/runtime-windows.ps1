param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Arguments)
$ErrorActionPreference='Stop'
$root=Join-Path $env:LOCALAPPDATA 'hermes-agentrouter'
$s=Get-Content -Raw (Join-Path $root 'settings.json') | ConvertFrom-Json
$env:HERMES_PROFILE='agentrouter'
$env:HERMES_AGENTROUTER_TOKEN_EFFICIENT='1'
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
    & $s.qwenCommand --bare --auth-type openai --model $s.model --approval-mode plan --output-format json --max-session-turns 1 --max-tool-calls 0 'Reply exactly AGENTROUTER_GLM52_OK'
  } elseif ($Arguments -contains '--desktop') {
    if (Get-Process -Name Hermes -ErrorAction SilentlyContinue) { throw 'Close Hermes completely before using the AgentRouter shortcut.' }
    $env:HERMES_HOME=$s.hermesRoot
    $env:HERMES_DESKTOP_USER_DATA_DIR=(Join-Path $root 'desktop-data')
    New-Item -ItemType Directory -Path $env:HERMES_DESKTOP_USER_DATA_DIR -Force | Out-Null
    $profileJson=@{profile='agentrouter'} | ConvertTo-Json
    [IO.File]::WriteAllText((Join-Path $env:HERMES_DESKTOP_USER_DATA_DIR 'active-profile.json'),$profileJson,[Text.UTF8Encoding]::new($false))
    Start-Process -FilePath $s.desktopExe -WorkingDirectory (Split-Path $s.desktopExe)
  } else {
    $env:HERMES_HOME=$s.profileHome
    & $s.hermesCli chat --provider copilot-acp --model 'glm-5.2' @Arguments
  }
} finally {
  if($ptr -ne [IntPtr]::Zero){[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)}
  $token=$null; $env:OPENAI_API_KEY=$null
}
