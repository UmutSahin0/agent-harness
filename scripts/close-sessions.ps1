$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$dir  = Join-Path $Root ".harness\sessions"
$n = @(Get-ChildItem $dir -Filter *.txt -ErrorAction SilentlyContinue).Count
Remove-Item (Join-Path $dir "*.txt") -ErrorAction SilentlyContinue
Add-Content -Encoding utf8 (Join-Path $Root ".harness\timeline.md") "$(Get-Date -Format 'HH:mm:ss') [orchestrator] $n oturum kapatildi"
Write-Output "$n ekip oturumu kapatildi."
