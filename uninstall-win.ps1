# ============================================================
# 윈도우 개발 환경 초기화 (클린 테스트용)
# 사용법: irm https://raw.githubusercontent.com/jsk3342/claude-setup/main/uninstall-win.ps1 | iex
# ============================================================

$ErrorActionPreference = "SilentlyContinue"

Write-Host ""
Write-Host "🧹 윈도우 개발 환경을 초기화합니다" -ForegroundColor White
Write-Host ""

# Claude Code (npm)
Write-Host "  Claude Code 제거..." -ForegroundColor Yellow
npm uninstall -g @anthropic-ai/claude-code 2>$null

# Scoop 앱 + Scoop 자체
if (Get-Command scoop -ErrorAction SilentlyContinue) {
    Write-Host "  Scoop 제거 (설치된 패키지 포함)..." -ForegroundColor Yellow
    scoop uninstall scoop -p 2>$null
}
if (Test-Path "$HOME\scoop") {
    Remove-Item -Recurse -Force "$HOME\scoop"
}

# winget으로 설치된 것 제거
if (Get-Command winget -ErrorAction SilentlyContinue) {
    Write-Host "  Node.js 제거..." -ForegroundColor Yellow
    winget uninstall OpenJS.NodeJS --silent 2>$null
    winget uninstall OpenJS.NodeJS.LTS --silent 2>$null

    Write-Host "  Python 제거..." -ForegroundColor Yellow
    winget uninstall Python.Python.3.12 --silent 2>$null
    winget uninstall Python.Python.3.13 --silent 2>$null

    Write-Host "  Git 제거..." -ForegroundColor Yellow
    winget uninstall Git.Git --silent 2>$null
}

# PATH 새로고침
$env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "User") + ";" + [System.Environment]::GetEnvironmentVariable("PATH", "Machine")

Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Blue
Write-Host "  ✅ 초기화 완료" -ForegroundColor Green
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Blue
Write-Host ""
Write-Host "  PowerShell을 재시작한 뒤 확인하세요:" -ForegroundColor White
Write-Host "  node --version     # 인식 안 되면 OK" -ForegroundColor Gray
Write-Host "  python --version   # 인식 안 되면 OK" -ForegroundColor Gray
Write-Host "  git --version      # 인식 안 되면 OK" -ForegroundColor Gray
Write-Host "  claude --version   # 인식 안 되면 OK" -ForegroundColor Gray
Write-Host "  scoop --version    # 인식 안 되면 OK" -ForegroundColor Gray
Write-Host ""
