# ============================================================
# 클로드 코드 올인원 설치 스크립트 (Windows PowerShell)
# 사용법: irm https://raw.githubusercontent.com/jsk3342/claude-setup/main/install.ps1 | iex
# ============================================================

$ErrorActionPreference = "Stop"

# ── 색상 함수 ──
function Write-Step {
    param([int]$Num, [int]$Total, [string]$Message, [string]$Reason)
    Write-Host ""
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Blue
    $done = $Num - 1
    $bar = ('■' * $done) + ('□' * ($Total - $done))
    Write-Progress -Id 71 -Activity 'Claude Code 올인원 설치' -Status "$Message · 진행 중" -PercentComplete ([int](100 * $done / $Total))
    Write-Host "  확인 완료 [$bar] $done/$Total (시간 진행률이 아닙니다)"
    Write-Host "  이유: $Reason"
    Write-Host "[$Num/$Total] $Message · 진행 중" -ForegroundColor White -NoNewline
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
    Write-Progress -Id 71 -Activity 'Claude Code 올인원 설치' -Completed
    # irm | iex로 실행되면 exit가 사용자 PowerShell 창을 닫아 안내를 못 읽는다. throw는 창을 남긴다.
    throw "설치를 중단했습니다."
}

function Test-Command {
    param([string]$Command)
    $null = Get-Command $Command -ErrorAction SilentlyContinue
    return $?
}

function Get-PythonVersion {
    foreach ($candidate in @("python", "python3")) {
        if (!(Test-Command $candidate)) {
            continue
        }

        $check = & {
            param([string]$Command)
            $ErrorActionPreference = "SilentlyContinue"
            try {
                $output = (& $Command --version 2>&1) -join ""
                $exitCode = $LASTEXITCODE
            }
            catch {
                $output = $_.Exception.Message
                $exitCode = 1
            }
            [PSCustomObject]@{
                Output = $output
                ExitCode = $exitCode
            }
        } $candidate

        if ($check.ExitCode -eq 0 -and $check.Output -match '^Python\s+\d+(?:\.\d+)+') {
            return $check.Output.Trim()
        }
    }

    return $null
}

function Refresh-Path {
    $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "User") + ";" + [System.Environment]::GetEnvironmentVariable("PATH", "Machine")
}

function Add-UserPathEntry {
    param([string]$Path)

    if (!(Test-Path $Path)) {
        return
    }

    $userPath = [System.Environment]::GetEnvironmentVariable("PATH", "User")
    $userEntries = @($userPath -split ";" | Where-Object { $_ -and $_ -ne $Path })
    $newUserPath = (@($Path) + $userEntries) -join ";"
    [System.Environment]::SetEnvironmentVariable("PATH", $newUserPath, "User")

    $processEntries = @($env:PATH -split ";" | Where-Object { $_ -and $_ -ne $Path })
    $env:PATH = (@($Path) + $processEntries) -join ";"
}

function Get-ClaudeCodeVersion {
    param([string]$CommandPath)

    if ([string]::IsNullOrWhiteSpace($CommandPath)) {
        return $null
    }

    # Older Claude Desktop versions can register this command alias.
    if ($CommandPath -like "$env:LOCALAPPDATA\Microsoft\WindowsApps\*") {
        return $null
    }

    $check = & {
        param([string]$Candidate)
        $ErrorActionPreference = "SilentlyContinue"
        try {
            $output = (& $Candidate --version 2>&1) -join ""
            $exitCode = $LASTEXITCODE
        }
        catch {
            $output = $_.Exception.Message
            $exitCode = 1
        }
        [PSCustomObject]@{
            Output = $output
            ExitCode = $exitCode
        }
    } $CommandPath

    if ($check.ExitCode -eq 0 -and $check.Output -match '\(Claude Code\)') {
        return $check.Output
    }

    return $null
}

function Get-ClaudeCommandPath {
    $command = Get-Command claude -ErrorAction SilentlyContinue
    if ($null -eq $command) {
        return $null
    }

    if (![string]::IsNullOrWhiteSpace($command.Source)) {
        return $command.Source
    }

    return $command.Name
}

function Test-SamePath {
    param([string]$Left, [string]$Right)

    if ([string]::IsNullOrWhiteSpace($Left) -or [string]::IsNullOrWhiteSpace($Right)) {
        return $false
    }

    try {
        $trimChars = [char[]]@('\', '/')
        $normalizedLeft = [System.IO.Path]::GetFullPath($Left).TrimEnd($trimChars)
        $normalizedRight = [System.IO.Path]::GetFullPath($Right).TrimEnd($trimChars)
        return [string]::Equals($normalizedLeft, $normalizedRight, [System.StringComparison]::OrdinalIgnoreCase)
    }
    catch {
        return $false
    }
}

Write-Host ""
Write-Host "🚀 클로드 코드 올인원 설치를 시작합니다" -ForegroundColor White
Write-Host "   Windows $([System.Environment]::OSVersion.Version)" -ForegroundColor Gray
Write-Host ""

$total = 7
$step = 0

# ── 1. Scoop (패키지 매니저) ──
$step++
Write-Step -Num $step -Total $total -Message "Scoop (패키지 매니저)" -Reason "필요한 도구를 하나씩 찾아 설치하지 않도록 도와줍니다."

if (Test-Command "scoop") {
    Write-Skip "Scoop"
} else {
    Write-Host "  Scoop를 설치합니다..."

    # Scoop 설치에 필요한 실행 정책 설정
    Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force

    # Scoop 설치기는 관리자 PowerShell을 기본 거부하므로 그때만 -RunAsAdmin을 넘긴다.
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    $scoopInstaller = [scriptblock]::Create((Invoke-RestMethod -Uri https://get.scoop.sh))
    $scoopArgs = @{}
    if ($isAdmin) {
        Write-Host "  ! 관리자 PowerShell이라 Scoop을 관리자 모드로 설치합니다." -ForegroundColor Yellow
        $scoopArgs.RunAsAdmin = $true
    }

    # Scoop 설치기는 거부할 때 break로 빠진다. 루프로 감싸야 이 스크립트까지 조용히 멈추지 않는다.
    foreach ($once in 1) {
        & $scoopInstaller @scoopArgs
    }

    Refresh-Path

    if (Test-Command "scoop") {
        Write-Ok "Scoop 설치 완료"
    } else {
        Write-Fail "Scoop 설치에 실패했습니다. PowerShell을 재시작한 뒤 다시 시도해주세요."
    }
}

# ── 2. Node.js ──
$step++
Write-Step -Num $step -Total $total -Message "Node.js" -Reason "앱과 사용량 표시 같은 추가 도구를 실행할 때 씁니다."

if (Test-Command "node") {
    $nodeVer = node -v
    Write-Skip "Node.js $nodeVer"
} else {
    Write-Host "  Node.js를 설치합니다..."
    scoop install nodejs

    Refresh-Path

    $nodeVer = node -v
    Write-Ok "Node.js $nodeVer 설치 완료"
}

# ── 3. Python 3 ──
$step++
Write-Step -Num $step -Total $total -Message "Python 3" -Reason "이후 자료 정리와 자동화 작업에 씁니다. 뉴스 대화 자체의 필수 조건은 아닙니다."

$pyVer = Get-PythonVersion
if ($null -ne $pyVer) {
    Write-Skip "$pyVer"
} else {
    Write-Host "  Python 3를 설치합니다..."
    scoop install python

    Refresh-Path

    $pyVer = Get-PythonVersion
    if ($null -eq $pyVer) {
        Write-Fail "Python 3 설치 후 실행 확인에 실패했습니다."
    }
    Write-Ok "$pyVer 설치 완료"
}

# ── 4. Git ──
$step++
Write-Step -Num $step -Total $total -Message "Git" -Reason "이후 작업 파일의 변경 내역을 관리하는 도구입니다."

if (Test-Command "git") {
    $gitVer = git --version
    Write-Skip "$gitVer"
} else {
    Write-Host "  Git을 설치합니다..."
    scoop install git

    Refresh-Path

    $gitVer = git --version
    Write-Ok "$gitVer 설치 완료"
}

# ── 5. Claude Code ──
$step++
Write-Step -Num $step -Total $total -Message "Claude Code" -Reason "컴퓨터에서 AI와 대화하고 작업을 맡기는 도구입니다."

# Only canonical installs can be skipped: their path can be repaired persistently.
Refresh-Path
$nativeClaudeDir = "$env:USERPROFILE\.local\bin"
$nativeClaudeExe = "$nativeClaudeDir\claude.exe"
$wingetLinksDir = "$env:LOCALAPPDATA\Microsoft\WinGet\Links"
$wingetClaudeExe = "$wingetLinksDir\claude.exe"
$verifiedClaudePath = $null
$claudeVer = $null

if (Test-Path $nativeClaudeExe) {
    Add-UserPathEntry $nativeClaudeDir
    $nativeClaudeVersion = Get-ClaudeCodeVersion $nativeClaudeExe
    if ($null -ne $nativeClaudeVersion) {
        $verifiedClaudePath = $nativeClaudeExe
        $claudeVer = $nativeClaudeVersion
    }
}

if ($null -eq $verifiedClaudePath -and (Test-Path $wingetClaudeExe)) {
    Add-UserPathEntry $wingetLinksDir
    $wingetClaudeVersion = Get-ClaudeCodeVersion $wingetClaudeExe
    if ($null -ne $wingetClaudeVersion) {
        $verifiedClaudePath = $wingetClaudeExe
        $claudeVer = $wingetClaudeVersion
    }
}

if ($null -ne $verifiedClaudePath) {
    Write-Skip "Claude Code"
} else {
    $claudeCommandPath = Get-ClaudeCommandPath
    if ($null -ne $claudeCommandPath) {
        $existingClaudeVersion = Get-ClaudeCodeVersion $claudeCommandPath
        if ($null -ne $existingClaudeVersion) {
            Write-Host "  ! 현재 PowerShell에서만 Claude Code가 보여 새 터미널에서도 실행되도록 복구합니다." -ForegroundColor Yellow
        } else {
            Write-Host "  ! 기존 claude 명령이 Claude Code가 아니거나 실행되지 않아 다시 설치합니다." -ForegroundColor Yellow
        }
    }

    Write-Host "  Claude Code를 설치합니다..."

    # Delegate download, checksum validation, and installation to Anthropic.
    $officialInstaller = Invoke-RestMethod -Uri https://claude.ai/install.ps1 -ErrorAction Stop

    # 갓 받은 claude.exe를 백신이 검사하는 동안 staging 폴더가 잠겨 EBUSY로 실패할 수 있다.
    # 잠금은 잠깐이라 남은 staging을 치우고 잠시 뒤 다시 시도한다.
    $stagingDir = "$env:USERPROFILE\.cache\claude\staging"
    $maxAttempts = 3
    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
        try {
            & ([scriptblock]::Create($officialInstaller)) stable
            break
        }
        catch {
            if ($attempt -eq $maxAttempts) {
                Write-Host "  $($_.Exception.Message)" -ForegroundColor Red
                Write-Fail "Claude Code 공식 설치기가 ${maxAttempts}번 실패했습니다. PC를 재시작한 뒤 같은 명령어를 다시 실행해주세요."
            }
            Write-Host "  ! 설치가 실패해 10초 뒤 다시 시도합니다 ($attempt/$maxAttempts): $($_.Exception.Message)" -ForegroundColor Yellow
            Start-Sleep -Seconds 10
            Remove-Item -Recurse -Force $stagingDir -ErrorAction SilentlyContinue
        }
    }

    Refresh-Path
    if (Test-Path $nativeClaudeExe) {
        Add-UserPathEntry $nativeClaudeDir
    }

    if (!(Test-Path $nativeClaudeExe)) {
        Write-Fail "Claude Code 공식 설치기가 네이티브 실행 파일을 만들지 못했습니다."
    }

    $claudeVer = Get-ClaudeCodeVersion $nativeClaudeExe
    if ($null -eq $claudeVer) {
        Write-Fail "Claude Code는 설치됐지만 네이티브 실행 확인에 실패했습니다."
    }

    $verifiedClaudePath = $nativeClaudeExe
}

# Confirm that future PowerShell sessions will resolve the verified install first.
$verifiedClaudeDir = Split-Path $verifiedClaudePath -Parent
$persistedUserPath = [System.Environment]::GetEnvironmentVariable("PATH", "User")
$persistedEntries = @($persistedUserPath -split ";" | Where-Object { $_ })
if ($persistedEntries.Count -eq 0 -or !(Test-SamePath $persistedEntries[0] $verifiedClaudeDir)) {
    Write-Fail "Claude Code는 설치됐지만 새 PowerShell에서 사용할 PATH 등록에 실패했습니다."
}

$finalClaudePath = Get-ClaudeCommandPath
$finalPathMatches = Test-SamePath $finalClaudePath $verifiedClaudePath
$finalClaudeVersion = Get-ClaudeCodeVersion $finalClaudePath
if (!$finalPathMatches -or $null -eq $finalClaudeVersion) {
    Write-Fail "Claude Code 명령어의 최종 실행 확인에 실패했습니다."
}

$claudeVer = $finalClaudeVersion
Write-Ok "Claude Code $claudeVer 설치 및 실행 확인"

# ── 6. Windows Terminal (앱 설치만, 꾸미기 없음) ──
$step++
Write-Step -Num $step -Total $total -Message "Windows Terminal" -Reason "Claude Code를 실행할 창을 준비합니다. 기존 배색, 폰트, 프로필은 유지합니다."
if (Get-Command wt.exe -ErrorAction SilentlyContinue) {
    Write-Skip "Windows Terminal"
} else {
    if (!(Test-Command "winget")) { Write-Fail "Windows Terminal 설치에 필요한 winget이 없습니다. Microsoft Store에서 Windows Terminal을 설치한 뒤 다시 실행하세요." }
    & winget install --id Microsoft.WindowsTerminal -e --source winget --accept-package-agreements --accept-source-agreements --disable-interactivity
    if ($LASTEXITCODE -ne 0) { Write-Fail "Windows Terminal 설치에 실패했습니다. 위 오류를 확인하세요." }
    $env:PATH = [Environment]::GetEnvironmentVariable('PATH', 'User') + ';' + [Environment]::GetEnvironmentVariable('PATH', 'Machine')
}
if (!(Get-Command wt.exe -ErrorAction SilentlyContinue)) { Write-Fail "Windows Terminal 실행 파일 확인에 실패했습니다. 새 PowerShell에서 다시 시도하세요." }
Write-Ok "Windows Terminal 실행 파일 확인"

# ── 7. 사용량 모드 ──
$step++
Write-Step -Num $step -Total $total -Message "사용량 모드" -Reason "Claude 사용 한도와 대화 상태를 표시합니다. 터미널 꾸미기와는 별개입니다."
$modeTemp = $null
$modeSource = $null
if ($PSScriptRoot -and (Test-Path (Join-Path $PSScriptRoot 'usage-mode\install.mjs'))) {
    $modeSource = Join-Path $PSScriptRoot 'usage-mode'
} else {
    $modeTemp = Join-Path ([IO.Path]::GetTempPath()) ('claude-usage-mode-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $modeTemp | Out-Null
    $modeSource = $modeTemp
}
try {
    if ($modeTemp) {
        $ref = if ($env:CLAUDE_SETUP_REF) { $env:CLAUDE_SETUP_REF } else { 'main' }
        foreach ($asset in @('install.mjs', 'usage-line.mjs', 'render.mjs', 'LICENSE')) {
            Invoke-WebRequest -UseBasicParsing "https://raw.githubusercontent.com/jsk3342/claude-setup/$ref/usage-mode/$asset" -OutFile (Join-Path $modeSource $asset)
        }
    }
    & node (Join-Path $modeSource 'install.mjs')
    if ($LASTEXITCODE -ne 0) { Write-Fail "사용량 모드 연결에 실패했습니다. 기존 설정을 확인하세요." }
} finally {
    if ($modeTemp) { Remove-Item -LiteralPath $modeTemp -Recurse -Force -ErrorAction SilentlyContinue }
}
Write-Ok "사용량 모드 설치 및 설정 연결 확인"
Write-Progress -Id 71 -Activity 'Claude Code 올인원 설치' -Completed
Write-Host "  확인 완료 [■■■■■■■] 7/7"

# ── 완료 ──
Write-Host ""
Write-Host "  설치된 항목:" -ForegroundColor White
Write-Host "  ✓ Scoop" -ForegroundColor Green
Write-Host "  ✓ Node.js   $nodeVer" -ForegroundColor Green
Write-Host "  ✓ Python    $pyVer" -ForegroundColor Green
Write-Host "  ✓ Git       $gitVer" -ForegroundColor Green
Write-Host "  ✓ Claude Code $claudeVer" -ForegroundColor Green
Write-Host "  ✓ Windows Terminal (기존 꾸미기 유지)" -ForegroundColor Green
Write-Host "  ✓ 사용량 모드" -ForegroundColor Green

Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Blue
Write-Host "  ✅ 설치가 모두 완료되었습니다!" -ForegroundColor Green
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Blue

Write-Host ""
Write-Host "  다음 단계:" -ForegroundColor White
Write-Host "  새 Windows Terminal을 열고 " -NoNewline
Write-Host "claude" -ForegroundColor Yellow -NoNewline
Write-Host " 를 입력하세요."
Write-Host "  처음 실행하면 Anthropic 계정 연결을 안내합니다."
Write-Host "  로그인 후 Claude 대화 화면에: 오늘 뉴스 정리해서 알려줘"
Write-Host "  설치 명령은 PowerShell에, 이 요청은 Claude 대화 화면에 입력합니다."
Write-Host "  다음에도 Windows Terminal을 열고 claude를 입력하면 됩니다. 다시 설치하지 않습니다."
Write-Host ""
Write-Host "  로그인에서 막힐 때:" -ForegroundColor White
Write-Host "  OAuth 400 또는 코드 붙여넣기 문제가 나면 " -NoNewline
Write-Host "claude auth login" -ForegroundColor Yellow -NoNewline
Write-Host " 으로 다시 로그인하세요."
Write-Host "  브라우저가 안 열리면 로그인 화면에서 " -NoNewline
Write-Host "c" -ForegroundColor Yellow -NoNewline
Write-Host " 를 눌러 주소를 복사한 뒤 Chrome에 붙여넣으세요."
Write-Host ""
