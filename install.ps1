# ============================================================
# 클로드 코드 올인원 설치 스크립트 (Windows PowerShell)
# 사용법: irm https://raw.githubusercontent.com/jsk3342/claude-setup/main/install.ps1 | iex
# ============================================================

$ErrorActionPreference = "Stop"

# ── 색상 함수 ──
function Write-Step {
    param([int]$Num, [int]$Total, [string]$Message)
    Write-Host ""
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Blue
    Write-Host "[$Num/$Total] $Message" -ForegroundColor White -NoNewline
    Write-Host "" -ForegroundColor White
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Blue
}

function Write-Ok {
    param([string]$Message)
    Write-Host "  ✓ $Message" -ForegroundColor Green
}

function Write-Skip {
    param([string]$Message)
    Write-Host "  → $Message (이미 설치됨, 스킵)" -ForegroundColor Yellow
}

function Write-Fail {
    param([string]$Message)
    Write-Host "  ✗ $Message" -ForegroundColor Red
    exit 1
}

function Test-Command {
    param([string]$Command)
    $null = Get-Command $Command -ErrorAction SilentlyContinue
    return $?
}

# ── 관리자 권한 확인 ──
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

Write-Host ""
Write-Host "🚀 클로드 코드 올인원 설치를 시작합니다" -ForegroundColor White
Write-Host "   Windows $([System.Environment]::OSVersion.Version)" -ForegroundColor Gray
Write-Host ""

$total = 4
$step = 0

# ── 1. Scoop (패키지 매니저) ──
$step++
Write-Step -Num $step -Total $total -Message "Scoop (패키지 매니저)"

if (Test-Command "scoop") {
    Write-Skip "Scoop"
} else {
    Write-Host "  Scoop를 설치합니다..."

    # Scoop 설치에 필요한 실행 정책 설정
    Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force

    # Scoop 설치
    Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression

    if (Test-Command "scoop") {
        Write-Ok "Scoop 설치 완료"
    } else {
        # PATH 새로고침
        $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "User") + ";" + [System.Environment]::GetEnvironmentVariable("PATH", "Machine")

        if (Test-Command "scoop") {
            Write-Ok "Scoop 설치 완료"
        } else {
            Write-Fail "Scoop 설치에 실패했습니다. PowerShell을 재시작한 뒤 다시 시도해주세요."
        }
    }
}

# ── 2. Node.js ──
$step++
Write-Step -Num $step -Total $total -Message "Node.js"

if (Test-Command "node") {
    $nodeVer = node -v
    Write-Skip "Node.js $nodeVer"
} else {
    Write-Host "  Node.js를 설치합니다..."
    scoop install nodejs

    # PATH 새로고침
    $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "User") + ";" + [System.Environment]::GetEnvironmentVariable("PATH", "Machine")

    $nodeVer = node -v
    Write-Ok "Node.js $nodeVer 설치 완료"
}

# ── 3. Python 3 ──
$step++
Write-Step -Num $step -Total $total -Message "Python 3"

if (Test-Command "python") {
    $pyVer = python --version 2>&1
    Write-Skip "$pyVer"
} elseif (Test-Command "python3") {
    $pyVer = python3 --version 2>&1
    Write-Skip "$pyVer"
} else {
    Write-Host "  Python 3를 설치합니다..."
    scoop install python

    # PATH 새로고침
    $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "User") + ";" + [System.Environment]::GetEnvironmentVariable("PATH", "Machine")

    $pyVer = python --version 2>&1
    Write-Ok "$pyVer 설치 완료"
}

# ── 4. Claude Code ──
$step++
Write-Step -Num $step -Total $total -Message "Claude Code"

if (Test-Command "claude") {
    Write-Skip "Claude Code"
} else {
    Write-Host "  Claude Code를 설치합니다..."
    npm install -g @anthropic-ai/claude-code

    # PATH 새로고침
    $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "User") + ";" + [System.Environment]::GetEnvironmentVariable("PATH", "Machine")

    Write-Ok "Claude Code 설치 완료"
}

# ── 완료 ──
Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Blue
Write-Host "  ✅ 설치가 모두 완료되었습니다!" -ForegroundColor Green
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Blue
Write-Host ""
Write-Host "  설치된 항목:" -ForegroundColor White

if (Test-Command "scoop") { Write-Host "  ✓ Scoop" -ForegroundColor Green }
if (Test-Command "node") { Write-Host "  ✓ Node.js   $(node -v)" -ForegroundColor Green }
if (Test-Command "python") { Write-Host "  ✓ Python    $(python --version 2>&1)" -ForegroundColor Green }
if (Test-Command "claude") { Write-Host "  ✓ Claude Code" -ForegroundColor Green }

Write-Host ""
Write-Host "  다음 단계:" -ForegroundColor White
Write-Host "  터미널에 " -NoNewline
Write-Host "claude" -ForegroundColor Yellow -NoNewline
Write-Host " 를 입력하면 클로드 코드가 실행됩니다."
Write-Host "  처음 실행하면 Anthropic 계정 연결을 안내합니다."
Write-Host ""
