# ============================================================
# 터미널 꾸미기 스크립트 (Oh My Posh)
# 사용법: irm https://raw.githubusercontent.com/jsk3342/claude-setup/main/customize.ps1 | iex
# ============================================================

$ErrorActionPreference = "SilentlyContinue"

Write-Host ""
Write-Host "🎨 터미널을 예쁘게 꾸며봅시다" -ForegroundColor White
Write-Host ""

# ── 1. Oh My Posh 설치 ──
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Blue
Write-Host "[1/3] Oh My Posh" -ForegroundColor White
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Blue

if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {
    Write-Host "  → Oh My Posh (이미 설치됨, 스킵)" -ForegroundColor Yellow
} else {
    Write-Host "  Oh My Posh를 설치합니다..."
    winget install JanDeDobbeleer.OhMyPosh --accept-source-agreements --accept-package-agreements
    $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "User") + ";" + [System.Environment]::GetEnvironmentVariable("PATH", "Machine")
    Write-Host "  ✓ Oh My Posh 설치 완료" -ForegroundColor Green
}

# ── 2. Nerd Font 설치 ──
Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Blue
Write-Host "[2/3] Nerd Font (MesloLGM)" -ForegroundColor White
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Blue

Write-Host "  폰트를 설치합니다 (아이콘 깨짐 방지)..."
oh-my-posh font install meslo
Write-Host "  ✓ 폰트 설치 완료" -ForegroundColor Green

# ── 3. PowerShell 프로필 설정 ──
Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Blue
Write-Host "[3/3] PowerShell 프로필 설정" -ForegroundColor White
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Blue

# 프로필 파일 없으면 생성
if (!(Test-Path $PROFILE)) {
    New-Item -ItemType File -Path $PROFILE -Force | Out-Null
    Write-Host "  ✓ 프로필 파일 생성" -ForegroundColor Green
}

# 이미 oh-my-posh 설정이 있으면 스킵
$profileContent = Get-Content $PROFILE -Raw -ErrorAction SilentlyContinue
if ($profileContent -match "oh-my-posh") {
    Write-Host "  → 프로필 이미 설정됨, 스킵" -ForegroundColor Yellow
} else {
    # 기본 테마(jandedobbeleer)로 초기 설정 — 나중에 원하는 걸로 교체 가능
    Add-Content $PROFILE "`noh-my-posh init pwsh --config `"`$env:POSH_THEMES_PATH\jandedobbeleer.omp.json`" | Invoke-Expression"
    Write-Host "  ✓ 프로필 설정 완료" -ForegroundColor Green
}

# ── 완료 ──
Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Blue
Write-Host "  ✅ 완료!" -ForegroundColor Green
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Blue
Write-Host ""
Write-Host "  🔤 폰트 적용 방법:" -ForegroundColor White
Write-Host "     Windows Terminal → 설정 → 프로필 → 모양 → 글꼴" -ForegroundColor Gray
Write-Host "     → 'MesloLGM Nerd Font' 선택 후 저장" -ForegroundColor Gray
Write-Host ""
Write-Host "  🎨 테마 변경 방법:" -ForegroundColor White
Write-Host "     1. 터미널 재시작 후 아래 명령어로 전체 테마 미리보기" -ForegroundColor Gray
Write-Host "        Get-PoshThemes" -ForegroundColor Yellow
Write-Host "     2. 마음에 드는 테마 이름 확인 (예: tokyo, catppuccin, paradox ...)" -ForegroundColor Gray
Write-Host "     3. 프로필 파일 열기" -ForegroundColor Gray
Write-Host "        notepad `$PROFILE" -ForegroundColor Yellow
Write-Host "     4. jandedobbeleer 부분을 원하는 테마 이름으로 교체 후 저장" -ForegroundColor Gray
Write-Host ""
Write-Host "  터미널을 재시작하면 적용됩니다 🚀" -ForegroundColor White
Write-Host ""
```

GitHub에 `customize.ps1`로 새 파일 추가하면 돼요. README에는 이렇게 안내:
```
# 선택사항 — 터미널 꾸미기
irm https://raw.githubusercontent.com/jsk3342/claude-setup/main/customize.ps1 | iex
