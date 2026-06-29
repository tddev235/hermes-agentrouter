[CmdletBinding()]param([switch]$KeepToken)
$ErrorActionPreference='Stop'
$root=Join-Path $env:LOCALAPPDATA 'hermes-agentrouter'
$hermes=Join-Path $env:LOCALAPPDATA 'hermes'
$backup=Join-Path $root 'config.before-agentrouter.yaml'
if(Test-Path $backup){Copy-Item $backup (Join-Path $hermes 'config.yaml') -Force}
$shortcut=Join-Path ([Environment]::GetFolderPath('Desktop')) 'Hermes - AgentRouter GLM 5.2.lnk'
if(Test-Path $shortcut){Remove-Item $shortcut -Force}
if(-not $KeepToken -and (Test-Path (Join-Path $root 'token.dpapi'))){Remove-Item (Join-Path $root 'token.dpapi') -Force}
Write-Host 'Hermes configuration restored. Remove the installation directory when ready:'
Write-Host $root

