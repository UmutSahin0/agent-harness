param(
  [Parameter(Mandatory=$true)][ValidateSet("claude","codex","cursor")][string]$Team,
  [Parameter(Mandatory=$true)][string]$Role,
  [Parameter(Mandatory=$true)][string]$InstructionFile,
  [Parameter(Mandatory=$true)][string]$OutFile,
  [string]$WorkDir = ".",
  [switch]$ReadOnly
)
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$Root     = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$RoleFile = Join-Path $Root "teams\$Team\roles\$Role.md"
if (-not (Test-Path $RoleFile)) { throw "Rol dosyasi yok: $RoleFile" }
$InstPath = (Resolve-Path $InstructionFile).Path
$OutPath  = [IO.Path]::GetFullPath($OutFile)
$LogPath  = [IO.Path]::ChangeExtension($OutPath, ".log")

$Cfg    = Get-Content (Join-Path $Root "teams\models.json") -Raw -Encoding utf8 | ConvertFrom-Json
$Model  = $Cfg.$Team.$Role.model
$Effort = $Cfg.$Team.$Role.effort
$Resume = [bool]$Cfg.$Team.$Role.resume

$SessDir  = Join-Path $Root ".harness\sessions"
New-Item -ItemType Directory -Force $SessDir | Out-Null
$SessFile = Join-Path $SessDir "$Team-$Role.txt"
$Sid = ""
if ($Resume -and (Test-Path $SessFile)) { $Sid = (Get-Content $SessFile -Raw).Trim() }

$Prompt = "Rol tanımın şu dosyada: $RoleFile . Talimatın şu dosyada: $InstPath . Önce ikisini de oku, sonra tamamen bu role göre talimatı uygula. Önceki çalışmaların hafızanda varsa oradan devam et; yoksa talimattaki çalışma klasöründeki raporları ve *-kanit.txt dosyalarını okuyarak devam et. Yapılmış işi baştan yapma."
if ($ReadOnly) { $Prompt += " ÖNEMLİ: Bu kısıt YALNIZCA senin bu yönetici adımın içindir: sen dosya oluşturma, değiştirme veya silme; sadece oku ve karar ver. Alt ajanlara (developer, reviewer, tester) bu kısıtı İLETME; onlar görevin izin verdiği şekilde dosya yazıp komut çalıştırır." }

function Invoke-Agent([string]$S) {
  $code = 1
  switch ($Team) {
    "codex" {
      $a = @("exec")
      if ($S) { $a += @("resume", $S) }
      $a += @("--dangerously-bypass-approvals-and-sandbox", "-o", $OutPath)
      if ($Model)  { $a += @("-m", $Model) }
      if ($Effort) { $a += @("-c", "model_reasoning_effort=$Effort") }
      $a += $Prompt
      & codex @a 2>&1 | ForEach-Object { "$_" } | Set-Content -Encoding utf8 $LogPath
      $code = $LASTEXITCODE
      if (-not $S) {
        $m = Select-String -Path $LogPath -Pattern 'session id:\s*(\S+)' | Select-Object -First 1
        if ($m) { $S = $m.Matches[0].Groups[1].Value }
      }
    }
    "cursor" {
      if ($Resume -and -not $S) { $S = ((& agent create-chat) | Out-String).Trim() }
      $a = @("--trust", "-p", "--output-format", "text")
      if (-not $ReadOnly) { $a += "--force" }
      if ($Model) { $a += @("--model", $Model) }
      if ($S)     { $a += @("--resume", $S) }
      $a += $Prompt
      $out = & agent @a 2>$LogPath | Out-String
      $code = $LASTEXITCODE
      $out | Set-Content -Encoding utf8 $OutPath
    }
    "claude" {
      $a = @("-p")
      if ($Model) { $a += @("--model", $Model) }
      if ($S) { $a += @("--resume", $S) }
      elseif ($Resume) { $S = [guid]::NewGuid().ToString(); $a += @("--session-id", $S) }
      if ($ReadOnly) { $a += @("--allowedTools", "Read,Grep,Glob") }
      else           { $a += @("--permission-mode", "acceptEdits", "--allowedTools", "Bash") }
      $out = $Prompt | & claude @a 2>$LogPath | Out-String
      $code = $LASTEXITCODE
      $out | Set-Content -Encoding utf8 $OutPath
    }
  }
  return @{ Code = $code; Sid = $S }
}

$label = if ($Model) { $Model } else { "varsayilan" }
if ($Effort) { $label += " / effort: $Effort" }
if ($Sid) { $label += " / oturuma devam" } elseif ($Resume) { $label += " / yeni oturum" }
Write-Host "[$Team/$Role] ($label) calisiyor..."

Push-Location $WorkDir
$ErrorActionPreference = "Continue"
try {
  $r = Invoke-Agent $Sid
  if ($r.Code -ne 0 -and $Sid) {
    Write-Host "[$Team/$Role] oturuma devam edilemedi, yeni oturum aciliyor..." -ForegroundColor Yellow
    Remove-Item $SessFile -ErrorAction SilentlyContinue
    $r = Invoke-Agent ""
  }
}
finally { Pop-Location; $ErrorActionPreference = "Stop" }

if ($r.Code -ne 0) { throw "[$Team/$Role] hata kodu: $($r.Code) (log: $LogPath)" }
if ($Resume -and $r.Sid) { $r.Sid | Set-Content -Encoding ascii $SessFile }
Write-Host "[$Team/$Role] bitti -> $OutPath"
