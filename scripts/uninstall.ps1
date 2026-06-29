[CmdletBinding()]param([switch]$KeepToken)
$ErrorActionPreference='Stop'
$root=Join-Path $env:LOCALAPPDATA 'hermes-agentrouter'
$hermes=Join-Path $env:LOCALAPPDATA 'hermes'
$desktop=[Environment]::GetFolderPath('Desktop')
foreach($name in @('Hermes - AgentRouter.lnk','Hermes - AgentRouter GLM 5.2.lnk')){$shortcut=Join-Path $desktop $name;if(Test-Path $shortcut){Remove-Item $shortcut -Force}}
$sourceRoot=Join-Path $hermes 'hermes-agent'
foreach($relative in @('agent\copilot_acp_client.py','agent\chat_completion_helpers.py','agent\conversation_loop.py','agent\title_generator.py','hermes_cli\models.py','hermes_cli\model_switch.py','hermes_cli\auth.py','hermes_cli\providers.py')){
  $file=Join-Path $sourceRoot $relative;$source="$file.before-agentrouter-plugin";if(Test-Path $source){Copy-Item $source $file -Force;Remove-Item $source -Force}
}
$bridgeModule=Join-Path $sourceRoot 'agent\hermes_agentrouter_bridge.py'
if(Test-Path $bridgeModule){Remove-Item $bridgeModule -Force}
$userPath=[Environment]::GetEnvironmentVariable('Path','User')
$clean=(($userPath -split ';' | Where-Object {$_ -and $_ -ne $root}) -join ';')
[Environment]::SetEnvironmentVariable('Path',$clean,'User')
if(-not $KeepToken -and (Test-Path (Join-Path $root 'token.dpapi'))){Remove-Item (Join-Path $root 'token.dpapi') -Force}
if(-not $KeepToken -and (Test-Path $root)){Remove-Item $root -Recurse -Force}
Write-Host 'Hermes AgentRouter uninstalled. The isolated agentrouter profile was preserved so its sessions are not lost.'
