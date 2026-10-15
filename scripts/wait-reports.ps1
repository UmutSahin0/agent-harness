param(
  [Parameter(Mandatory=$true)][string]$Reports,   # ornek: T10-codex,T11-cursor
  [int]$TimeoutSec = 540
)
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$Root  = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$names = $Reports -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
$deadline = (Get-Date).AddSeconds($TimeoutSec)

do {
  $pending = @($names | Where-Object { -not (Test-Path (Join-Path $Root ".harness\reports\$_.md")) })
  if ($pending.Count -eq 0) { break }
  Start-Sleep -Seconds 15
} while ((Get-Date) -lt $deadline)

foreach ($r in $names) {
  $p = Join-Path $Root ".harness\reports\$r.md"
  if (Test-Path $p) {
    $head = Get-Content $p -Encoding utf8 -TotalCount 3
    Write-Output "[$r] $($head[1]) | $($head[2])"
    Write-Output "   rapor: .harness/reports/$r.md"
  } else {
    Write-Output "[$r] HALA CALISIYOR"
  }
}
