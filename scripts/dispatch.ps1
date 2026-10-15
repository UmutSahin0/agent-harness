param(
  [Parameter(Mandatory=$true)][ValidateSet("claude","codex","cursor")][string]$Team,
  [Parameter(Mandatory=$true)][string]$TaskFile,
  [int]$MaxSteps = 8
)
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$Root     = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$TaskPath = (Resolve-Path $TaskFile).Path
$Id       = [IO.Path]::GetFileNameWithoutExtension($TaskPath)
$Report   = Join-Path $Root ".harness\reports\$Id-$Team.md"
Remove-Item $Report -ErrorAction SilentlyContinue   # eski rapor bekleyeni yaniltmasin

$tm  = Join-Path $PSScriptRoot "team-manager.ps1"
$cmd = "`$host.UI.RawUI.WindowTitle = '$Id - $Team ekibi'; Set-Location '$Root'; & '$tm' -Team $Team -TaskFile '$TaskPath' -MaxSteps $MaxSteps"
$enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($cmd))
Start-Process powershell.exe -ArgumentList "-NoExit","-ExecutionPolicy","Bypass","-EncodedCommand",$enc

Add-Content -Encoding utf8 (Join-Path $Root ".harness\timeline.md") "$(Get-Date -Format 'HH:mm:ss') [orchestrator] $Id -> $Team ekibi"
Write-Output "BASLATILDI: $Id -> $Team ekibi. Beklenecek rapor: $Id-$Team"
