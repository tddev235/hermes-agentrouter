param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Arguments)
$ErrorActionPreference='Stop'
$root=Join-Path $env:LOCALAPPDATA 'hermes-agentrouter'
$s=Get-Content -Raw (Join-Path $root 'settings.json') | ConvertFrom-Json
$encoded=(Get-Content -Raw (Join-Path $root 'token.dpapi')).TrimStart([char]0xFEFF).Trim()
$secure=$encoded | ConvertTo-SecureString
$ptr=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
try {
  $token=[Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
  $env:OPENAI_API_KEY=$token; $env:OPENAI_BASE_URL=$s.baseUrl; $env:OPENAI_MODEL=$s.model
  $env:HERMES_COPILOT_ACP_COMMAND=$s.qwenCommand
  $env:HERMES_COPILOT_ACP_ARGS='--acp --bare --auth-type openai --model {model}'
  $env:PYTHONUTF8='1'; $env:PATH="$(Split-Path $s.qwenCommand);$env:PATH"
  if ($Arguments -contains '--check') {
    & $s.qwenCommand --bare --auth-type openai --model $s.model --approval-mode plan --output-format json --max-session-turns 1 --max-tool-calls 0 'Reply exactly AGENTROUTER_GLM52_OK'
  } elseif ($Arguments -contains '--desktop') {
    if (Get-Process -Name Hermes -ErrorAction SilentlyContinue) { throw 'Close Hermes completely before using the AgentRouter shortcut.' }
    Start-Process -FilePath $s.desktopExe -WorkingDirectory (Split-Path $s.desktopExe)
  } else {
    & $s.hermesCli chat --provider copilot-acp --model $s.model @Arguments
  }
} finally {
  if($ptr -ne [IntPtr]::Zero){[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)}
  $token=$null; $env:OPENAI_API_KEY=$null
}
