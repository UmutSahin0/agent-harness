param(
  [Parameter(Mandatory=$true)][ValidateSet("claude","codex","cursor")][string]$Team,
  [Parameter(Mandatory=$true)][string]$TaskFile,
  [string]$WorkDir = ".",
  [int]$MaxSteps = 8
)
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$Root     = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$TaskPath = (Resolve-Path $TaskFile).Path
$Id       = [IO.Path]::GetFileNameWithoutExtension($TaskPath)
$Stamp    = Get-Date -Format "yyyyMMdd-HHmmss"
$RunDir   = Join-Path $Root ".harness\runs\$Id-$Team-$Stamp"
New-Item -ItemType Directory -Force $RunDir | Out-Null
$History  = Join-Path $RunDir "history.md"
$Timeline = Join-Path $Root ".harness\timeline.md"
$RunAgent = Join-Path $PSScriptRoot "run-agent.ps1"

$SubRoles = @(Get-ChildItem (Join-Path $Root "teams\$Team\roles") -Filter *.md |
  ForEach-Object { $_.BaseName } | Where-Object { $_ -ne "manager" })

function Log($msg, $color = "Gray") {
  $line = "$(Get-Date -Format 'HH:mm:ss') [$Id][$Team] $msg"
  Write-Host $line -ForegroundColor $color
  Add-Content -Encoding utf8 $Timeline $line
}

"# $Id - $Team ekibi gecmisi`n" | Set-Content -Encoding utf8 $History
Log "Gorev alindi. Alt ajanlar: $($SubRoles -join ', ')" "Cyan"

$final = $null
for ($n = 1; $n -le $MaxSteps; $n++) {
  # ---- 1) Yoneticiye sor ----
  $mIn  = Join-Path $RunDir ("{0:D2}-manager-input.md" -f $n)
  $mOut = Join-Path $RunDir ("{0:D2}-manager.md" -f $n)
  $mText = @"
# Yonetici karari - Adim $n / $MaxSteps
Gorev dosyasi: $TaskPath
Ekibindeki alt ajanlar: $($SubRoles -join ', ')
Simdiye kadarki gecmis: $History
Kalan adim hakki: $($MaxSteps - $n + 1)
"@
  $mText | Set-Content -Encoding utf8 $mIn

  Log "manager karar veriyor..." "Yellow"
  try { & $RunAgent -Team $Team -Role manager -InstructionFile $mIn -OutFile $mOut -ReadOnly }
  catch { Log "manager calisirken hata: $_" "Red"; continue }

  # ---- 2) Kararini JSON olarak oku ----
  $raw = Get-Content $mOut -Raw -Encoding utf8
  $d = $null
  $s = $raw.IndexOf("{"); $e = $raw.LastIndexOf("}")
  if ($s -ge 0 -and $e -gt $s) { try { $d = $raw.Substring($s, $e - $s + 1) | ConvertFrom-Json } catch {} }
  if (-not $d) {
    Log "manager gecerli JSON dondurmedi, tekrar sorulacak (bkz. $mOut)" "Red"
    Add-Content -Encoding utf8 $History "`n## Adim ${n}: HATA`nYonetici gecerli JSON dondurmedi. Bir dahaki cevap SADECE JSON olmali.`n"
    continue
  }

  if ($d.action -eq "done") {
    $final = $d
    Log "manager -> BITTI ($($d.status)): $($d.summary)" "Green"
    break
  }

  $role = "$($d.role)"
  if ($SubRoles -notcontains $role) {
    Log "manager olmayan bir ajan secti: '$role'" "Red"
    Add-Content -Encoding utf8 $History "`n## Adim ${n}: HATA`n'$role' diye bir alt ajan yok. Secenekler: $($SubRoles -join ', ')`n"
    continue
  }

  Log "manager -> $role : $($d.instruction)" "Magenta"
  Log "   neden: $($d.reason)" "DarkGray"

  # ---- 3) Alt ajani calistir ----
  $sIn  = Join-Path $RunDir ("{0:D2}-$role-input.md" -f $n)
  $sOut = Join-Path $RunDir ("{0:D2}-$role.md" -f $n)
  $sText = @"
# $Id - Adim $n
Ana gorev dosyasi (kapsam ve kabul kriterleri icin oku): $TaskPath
Calisma klasoru (onceki adimlarin raporlari ve kanitlari): $RunDir
Kanit dosyan: $(Join-Path $RunDir ("{0:D2}-$role-kanit.txt" -f $n))

## Yoneticinin sana talimati
$($d.instruction)
"@
  $sText | Set-Content -Encoding utf8 $sIn

  try {
    & $RunAgent -Team $Team -Role $role -InstructionFile $sIn -OutFile $sOut -WorkDir $WorkDir
    $res = Get-Content $sOut -Raw -Encoding utf8
  } catch { $res = "HATA: $_`nDURUM: SORUNLU" }

  $durum = "?"
  $mm = [regex]::Matches("$res", 'DURUM:\s*(OK|SORUNLU)')
  if ($mm.Count -gt 0) { $durum = $mm[$mm.Count - 1].Groups[1].Value }
  $renk = if ($durum -eq "OK") { "Green" } else { "Red" }
  Log "$role bitti -> DURUM: $durum" $renk

  # ---- 4) Gecmise yaz ----
  $short = if ("$res".Length -gt 3000) { "...(kisaltildi)`n" + "$res".Substring("$res".Length - 3000) } else { "$res" }
  $entry = @"

## Adim ${n}: manager -> $role
Talimat: $($d.instruction)
Neden: $($d.reason)
Sonuc: DURUM: $durum
Tam cikti dosyasi: $sOut

$short
"@
  Add-Content -Encoding utf8 $History $entry
}

if (-not $final) {
  Log "Adim limiti ($MaxSteps) doldu, gorev bitirilemedi" "Red"
  $final = [pscustomobject]@{ status = "SORUNLU"; summary = "Adim limiti doldu" }
}

$Report = Join-Path $Root ".harness\reports\$Id-$Team.md"
$hdr = @"
# $Id - $Team ekibi raporu
Durum: $($final.status)
Ozet: $($final.summary)
Calisma klasoru: $RunDir

"@
($hdr + (Get-Content $History -Raw -Encoding utf8)) | Set-Content -Encoding utf8 $Report
Log "Rapor: $Report" "Cyan"

