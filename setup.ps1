#requires -version 5.0

param(
    [switch]$Force
)

Write-Host "Agent Harness Setup" -ForegroundColor Cyan
Write-Host "==================" -ForegroundColor Cyan

# 1. Python kontrol
Write-Host "`n[1/4] Python versiyonu kontrol ediliyor..." -ForegroundColor Yellow
try {
    $pythonVersion = python --version 2>&1
    if ($pythonVersion -match "Python (\d+\.\d+)") {
        Write-Host "  ✓ $pythonVersion bulundu" -ForegroundColor Green
    } else {
        throw "Python bulunamadı"
    }
} catch {
    Write-Host "  ✗ Python 3.8+ gereklidir. https://www.python.org" -ForegroundColor Red
    exit 1
}

# 2. Klasör yapısı oluştur
Write-Host "`n[2/4] Klasör yapısı hazırlanıyor..." -ForegroundColor Yellow
$folders = @(
    ".harness\tasks",
    ".harness\reports",
    ".harness\runs",
    ".harness\sessions"
)

foreach ($folder in $folders) {
    if (-not (Test-Path $folder)) {
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
        Write-Host "  ✓ $folder oluşturuldu" -ForegroundColor Green
    } else {
        Write-Host "  ✓ $folder zaten var" -ForegroundColor Green
    }
}

# 3. .env kontrol
Write-Host "`n[3/4] Ortam değişkenleri kontrol ediliyor..." -ForegroundColor Yellow
if (-not (Test-Path ".env")) {
    if (Test-Path ".env.example") {
        Copy-Item ".env.example" ".env"
        Write-Host "  ✓ .env.example'den .env oluşturuldu" -ForegroundColor Green
        Write-Host "  ⚠ .env dosyasını doldur (API keyleri vb.)" -ForegroundColor Yellow
    }
} else {
    Write-Host "  ✓ .env zaten var" -ForegroundColor Green
}

# 4. Bağımlılıklar (isteğe bağlı — ekip scriptleri kendi deps'lerini yüklüyor)
Write-Host "`n[4/4] Sistem doğrulanıyor..." -ForegroundColor Yellow
if (Test-Path "requirements.txt") {
    $installReqs = $false
    if ($Force) {
        $installReqs = $true
    } else {
        $response = Read-Host "  requirements.txt bulundu. Python bağımlılıklarını kur mu? (y/n)"
        $installReqs = ($response -eq 'y' -or $response -eq 'Y')
    }

    if ($installReqs) {
        Write-Host "  → pip install -r requirements.txt çalıştırılıyor..." -ForegroundColor Cyan
        pip install -r requirements.txt -q
        Write-Host "  ✓ Bağımlılıklar yüklendi" -ForegroundColor Green
    }
}

# Scripts var mı kontrol et
$requiredScripts = @(
    "scripts\dispatch.ps1",
    "scripts\wait-reports.ps1",
    "scripts\close-sessions.ps1"
)

$allScriptsFound = $true
foreach ($script in $requiredScripts) {
    if (-not (Test-Path $script)) {
        Write-Host "  ✗ $script bulunamadı!" -ForegroundColor Red
        $allScriptsFound = $false
    }
}

if ($allScriptsFound) {
    Write-Host "  ✓ Tüm script'ler hazır" -ForegroundColor Green
}

# Özet
Write-Host "`n" -ForegroundColor Cyan
Write-Host "✓ Kurulum tamamlandı!" -ForegroundColor Green
Write-Host "`nSonraki adımlar:" -ForegroundColor Cyan
Write-Host "  1. .env dosyasını API keyleri ile doldur (varsa)"
Write-Host "  2. .harness/tasks/T0.md adında görev dosyası oluştur"
Write-Host "  3. .\scripts\dispatch.ps1 -Team <ekip> -TaskFile .harness\tasks\T0.md ile başlat"
Write-Host "  4. .\scripts\wait-reports.ps1 -Reports T0-<ekip> ile raporları bekle"
Write-Host "`nKullanım: README.md dosyasını oku" -ForegroundColor Cyan
