# ============================================================
# 윈도우 개발 환경 초기화 (클린 테스트용)
# 사용법: irm https://raw.githubusercontent.com/jsk3342/claude-setup/main/uninstall-win.ps1 | iex
# ============================================================

$ErrorActionPreference = "SilentlyContinue"

function Test-SamePath {
    param([string]$Left, [string]$Right)

    if ([string]::IsNullOrWhiteSpace($Left) -or [string]::IsNullOrWhiteSpace($Right)) {
        return $false
    }

    try {
        $trimChars = [char[]]@('\', '/')
        $expandedLeft = [System.Environment]::ExpandEnvironmentVariables($Left.Trim().Trim('"'))
        $expandedRight = [System.Environment]::ExpandEnvironmentVariables($Right.Trim().Trim('"'))
        $normalizedLeft = [System.IO.Path]::GetFullPath($expandedLeft).TrimEnd($trimChars)
        $normalizedRight = [System.IO.Path]::GetFullPath($expandedRight).TrimEnd($trimChars)
        return [string]::Equals($normalizedLeft, $normalizedRight, [System.StringComparison]::OrdinalIgnoreCase)
    }
    catch {
        return $false
    }
}

function Test-UserPathEntry {
    param([string]$Path)

    $userPath = [System.Environment]::GetEnvironmentVariable("PATH", "User")
    foreach ($entry in @($userPath -split ";" | Where-Object { $_ })) {
        if (Test-SamePath $entry $Path) {
            return $true
        }
    }

    return $false
}

function Remove-UserPathEntry {
    param([string]$Path)

    $userPath = [System.Environment]::GetEnvironmentVariable("PATH", "User")
    $keptUserEntries = @()
    $removed = $false

    foreach ($entry in @($userPath -split ";" | Where-Object { $_ })) {
        if (Test-SamePath $entry $Path) {
            $removed = $true
        } else {
            $keptUserEntries += $entry
        }
    }

    if ($removed) {
        [System.Environment]::SetEnvironmentVariable("PATH", ($keptUserEntries -join ";"), "User")
    }

    $keptProcessEntries = @()
    foreach ($entry in @($env:PATH -split ";" | Where-Object { $_ })) {
        if (!(Test-SamePath $entry $Path)) {
            $keptProcessEntries += $entry
        }
    }
    $env:PATH = $keptProcessEntries -join ";"

    return $removed
}

Write-Host ""
Write-Host "🧹 윈도우 개발 환경을 초기화합니다" -ForegroundColor White
Write-Host "  현재 사용자: $([Security.Principal.WindowsIdentity]::GetCurrent().Name)" -ForegroundColor Gray
Write-Host "  WinGet 제거 중 필요한 경우 Windows가 관리자 승인을 요청할 수 있습니다." -ForegroundColor Gray
Write-Host ""

# Claude Code (npm)
Write-Host "  Claude Code 제거..." -ForegroundColor Yellow
$knownNpmClaudePaths = @()
$knownNpmClaudeShims = @()
if (Get-Command npm -ErrorAction SilentlyContinue) {
    $npmRootBeforeRemoval = (& npm root -g 2>$null | Select-Object -First 1)
    if ($npmRootBeforeRemoval) {
        $knownNpmClaudePaths += (Join-Path $npmRootBeforeRemoval "@anthropic-ai\claude-code")
        $npmPrefixBeforeRemoval = Split-Path $npmRootBeforeRemoval -Parent
        foreach ($shimName in @("claude", "claude.cmd", "claude.ps1")) {
            $knownNpmClaudeShims += (Join-Path $npmPrefixBeforeRemoval $shimName)
        }
    }
}
if ($env:APPDATA) {
    $knownNpmClaudePaths += "$env:APPDATA\npm\node_modules\@anthropic-ai\claude-code"
    foreach ($shimName in @("claude", "claude.cmd", "claude.ps1")) {
        $knownNpmClaudeShims += "$env:APPDATA\npm\$shimName"
    }
}
$knownNpmClaudePaths = @($knownNpmClaudePaths | Select-Object -Unique)
$knownNpmClaudeShims = @($knownNpmClaudeShims | Select-Object -Unique)

npm uninstall -g @anthropic-ai/claude-code 2>$null

# Claude Code (Anthropic native installer)
$nativeClaudeDir = "$env:USERPROFILE\.local\bin"
$nativeClaudeBin = "$nativeClaudeDir\claude.exe"
$nativeClaudeVersions = "$env:USERPROFILE\.local\share\claude"
$legacyClaudeLocal = "$env:USERPROFILE\.claude\local"
$legacyClaudeBin = "$legacyClaudeLocal\bin"

Remove-Item -Path $nativeClaudeBin -Force -ErrorAction SilentlyContinue
Remove-Item -Path $nativeClaudeVersions -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path $legacyClaudeLocal -Recurse -Force -ErrorAction SilentlyContinue

$nativePathKeptForOtherTools = $false
$nativeDirContents = @()
$nativePathCanBeRemoved = !(Test-Path $nativeClaudeDir)
if (!$nativePathCanBeRemoved) {
    try {
        $nativeDirContents = @(Get-ChildItem -Path $nativeClaudeDir -Force -ErrorAction Stop)
        $nativePathCanBeRemoved = $nativeDirContents.Count -eq 0
    }
    catch {
        $nativePathCanBeRemoved = $false
    }
}
if ($nativePathCanBeRemoved) {
    Remove-Item -Path $nativeClaudeDir -Force -ErrorAction SilentlyContinue
    $null = Remove-UserPathEntry $nativeClaudeDir
} elseif (Test-UserPathEntry $nativeClaudeDir) {
    $nativePathKeptForOtherTools = $true
}

# These legacy paths are Claude-specific and are dead after removing the directory.
$null = Remove-UserPathEntry $legacyClaudeLocal
$null = Remove-UserPathEntry $legacyClaudeBin

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
    Write-Host "  Claude Code(WinGet) 제거..." -ForegroundColor Yellow
    winget uninstall --id Anthropic.ClaudeCode -e --silent 2>$null

    Write-Host "  Node.js 제거..." -ForegroundColor Yellow
    winget uninstall OpenJS.NodeJS --silent 2>$null
    winget uninstall OpenJS.NodeJS.LTS --silent 2>$null
    winget uninstall OpenJS.NodeJS.22 --silent 2>$null
    winget uninstall OpenJS.NodeJS.20 --silent 2>$null
    winget uninstall OpenJS.NodeJS.18 --silent 2>$null

    Write-Host "  Python 제거..." -ForegroundColor Yellow
    winget uninstall Python.Python.3.12 --silent 2>$null
    winget uninstall Python.Python.3.13 --silent 2>$null
    winget uninstall Python.Python.3.11 --silent 2>$null

    Write-Host "  Git 제거..." -ForegroundColor Yellow
    winget uninstall Git.Git --silent 2>$null
    winget uninstall Git.Git.2 --silent 2>$null
}

# PATH 새로고침
$env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "User") + ";" + [System.Environment]::GetEnvironmentVariable("PATH", "Machine")

# Claude Code 제거가 실제로 끝났는지 확인
$claudeResidue = @()
foreach ($knownPath in @($nativeClaudeBin, $nativeClaudeVersions, $legacyClaudeLocal)) {
    if (Test-Path $knownPath) {
        $claudeResidue += $knownPath
    }
}

foreach ($npmClaudePath in $knownNpmClaudePaths) {
    if (Test-Path $npmClaudePath) {
        $claudeResidue += $npmClaudePath
    }
}
foreach ($npmClaudeShim in $knownNpmClaudeShims) {
    if (Test-Path $npmClaudeShim) {
        $claudeResidue += $npmClaudeShim
    }
}

if ($nativePathCanBeRemoved -and (Test-UserPathEntry $nativeClaudeDir)) {
    $claudeResidue += "User PATH: $nativeClaudeDir"
}
foreach ($legacyPath in @($legacyClaudeLocal, $legacyClaudeBin)) {
    if (Test-UserPathEntry $legacyPath) {
        $claudeResidue += "User PATH: $legacyPath"
    }
}

$wingetPackageRoot = "$env:LOCALAPPDATA\Microsoft\WinGet\Packages"
if (Test-Path $wingetPackageRoot) {
    $wingetClaudePackages = @(Get-ChildItem -Path $wingetPackageRoot -Directory -Filter "Anthropic.ClaudeCode_*" -ErrorAction SilentlyContinue)
    foreach ($package in $wingetClaudePackages) {
        $claudeResidue += $package.FullName
    }
}

$wingetClaudeLink = "$env:LOCALAPPDATA\Microsoft\WinGet\Links\claude.exe"
$linkItem = Get-Item -LiteralPath $wingetClaudeLink -Force -ErrorAction SilentlyContinue
if ($linkItem -and (($linkItem.Target -join ";") -match "Anthropic\.ClaudeCode")) {
    $claudeResidue += $wingetClaudeLink
}

if (Get-Command winget -ErrorAction SilentlyContinue) {
    $wingetList = (& winget list --id Anthropic.ClaudeCode -e 2>$null) -join "`n"
    if ($LASTEXITCODE -eq 0 -and $wingetList -match "Anthropic\.ClaudeCode") {
        $claudeResidue += "WinGet: Anthropic.ClaudeCode"
    }
}

$claudeResidue = @($claudeResidue | Select-Object -Unique)
if ($claudeResidue.Count -gt 0) {
    Write-Host ""
    Write-Host "  ✗ Claude Code 제거가 완료되지 않았습니다:" -ForegroundColor Red
    foreach ($residue in $claudeResidue) {
        Write-Host "    - $residue" -ForegroundColor Red
    }
    Write-Host "  위 항목을 확인한 뒤 초기화 스크립트를 다시 실행하세요." -ForegroundColor Yellow
    exit 1
}

if ($nativePathKeptForOtherTools) {
    Write-Host ""
    Write-Host "  ⚠ $nativeClaudeDir 공유 경로를 안전하게 제거할 수 없어 PATH는 유지했습니다." -ForegroundColor Yellow
    Write-Host "    Claude 제거는 끝났지만 PATH 등록까지 완전히 빈 상태로 시험하려면 새 Windows 사용자나 VM을 사용하세요." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Blue
Write-Host "  ✅ 초기화 완료" -ForegroundColor Green
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Blue
Write-Host ""
Write-Host "  PowerShell을 재시작한 뒤 확인하세요:" -ForegroundColor White
Write-Host "  node --version     # 인식 안 되면 OK" -ForegroundColor Gray
Write-Host "  python --version   # 인식 안 되면 OK" -ForegroundColor Gray
Write-Host "  git --version      # 인식 안 되면 OK" -ForegroundColor Gray
Write-Host "  scoop --version    # 인식 안 되면 OK" -ForegroundColor Gray
Write-Host "  Claude Desktop이 설치돼 있으면 claude 명령은 남아 있을 수 있습니다." -ForegroundColor Gray
Write-Host ""
