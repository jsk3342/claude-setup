# ============================================================
# 클로드 코드 올인원 설치 스크립트 (Windows PowerShell)
# 사용법: irm https://raw.githubusercontent.com/jsk3342/claude-setup/main/install.ps1 | iex
# ============================================================

$ErrorActionPreference = "Stop"

# Windows PowerShell 5.1의 진행 막대는 한국어 콘솔에서 화면을 저장하다 IndexOutOfRangeException을 낼 수 있고,
# 위의 Stop 때문에 설치 전체가 끊긴다. 단계는 아래 글로 보여 주므로 막대를 쓰지 않는다.
$savedProgressPreference = $ProgressPreference
$ProgressPreference = 'SilentlyContinue'

$script:installStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$script:currentStepLabel = "시작 전"
$script:stepHeartbeat = $null

# 설치 명령이 조용히 도는 동안 멈춘 것처럼 보이지 않게 15초마다 경과 시간을 찍는다.
# 공식 설치기를 이 창에서 그대로 돌리므로, 별도 실행 공간에서 콘솔에 직접 쓴다.
function Stop-StepHeartbeat {
    if ($null -ne $script:stepHeartbeat) {
        $script:stepHeartbeat.Stop()
        $script:stepHeartbeat.Dispose()
        $script:stepHeartbeat = $null
    }
}

function Start-StepHeartbeat {
    Stop-StepHeartbeat
    $heartbeat = [powershell]::Create()
    $null = $heartbeat.AddScript({
        $watch = [System.Diagnostics.Stopwatch]::StartNew()
        # 정리가 어떻게든 빠져도 사용자 창에 영원히 찍히지 않도록 상한을 둔다.
        while ($watch.Elapsed.TotalMinutes -lt 60) {
            Start-Sleep -Seconds 15
            # 다른 프로그램이 줄을 끝내지 않은 채 쓰는 중이면 줄을 바꿔 글이 이어 붙지 않게 한다.
            try { if ([Console]::CursorLeft -gt 0) { [Console]::WriteLine() } } catch { }
            [Console]::WriteLine("  설치 작업 실행 중 · 경과 $([int]$watch.Elapsed.TotalSeconds)초 · 완료 문구를 기다려주세요.")
        }
    })
    $null = $heartbeat.BeginInvoke()
    $script:stepHeartbeat = $heartbeat
}

# 실패하면 고객이 여러 번 나눠 붙여넣지 않도록 진단에 필요한 내용을 한 덩어리로 보여 준다.
function Write-FailureReport {
    param([string]$Message)
    $safeMessage = $Message
    if ($env:USERPROFILE) { $safeMessage = $safeMessage.Replace($env:USERPROFILE, '~') }
    $safeMessage = ($safeMessage -replace '\s+', ' ').Trim()
    if ($safeMessage.Length -gt 800) { $safeMessage = $safeMessage.Substring(0, 800) + ' ...' }
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    $width = try { $Host.UI.RawUI.BufferSize.Width } catch { '알 수 없음' }
    $report = @(
        '---------- 설치 실패 보고 시작 ----------'
        '설치기: claude-setup (윈도우)'
        '결과: 중단됨'
        "단계: $script:currentStepLabel"
        "오류: $safeMessage"
        "걸린 시간: $([int]$script:installStopwatch.Elapsed.TotalSeconds)초"
        "OS: Windows $([System.Environment]::OSVersion.Version)"
        "칩: $env:PROCESSOR_ARCHITECTURE"
        "PowerShell: $($PSVersionTable.PSVersion) / 코드페이지 $([Console]::OutputEncoding.CodePage) / 창 폭 $width / 관리자 $isAdmin"
        '---------- 설치 실패 보고 끝 ----------'
    ) -join "`r`n"
    Write-Host ""
    Write-Host $report
    $copied = $false
    try {
        Set-Clipboard -Value $report
        $copied = ((Get-Clipboard -Raw).Trim() -eq $report.Trim())
    }
    catch { $copied = $false }
    if ($copied) {
        Write-Host "  위 보고를 복사해 두었습니다. 설치 도우미 입력칸에 그대로 붙여넣어 주세요." -ForegroundColor Yellow
    } else {
        Write-Host "  위 보고를 시작 줄부터 끝 줄까지 복사해 설치 도우미 입력칸에 붙여넣어 주세요." -ForegroundColor Yellow
    }
}

# ── 색상 함수 ──
function Write-Step {
    param([int]$Num, [int]$Total, [string]$Message, [string]$Reason)
    $script:currentStepLabel = "$Num/$Total $Message"
    Start-StepHeartbeat
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Blue
    $done = $Num - 1
    $bar = ('■' * $done) + ('□' * ($Total - $done))
    Write-Host "  확인 완료 [$bar] $done/$Total (시간 진행률이 아닙니다)"
    Write-Host "  이유: $Reason"
    Write-Host "[$Num/$Total] $Message · 진행 중" -ForegroundColor White -NoNewline
    Write-Host "" -ForegroundColor White
    Write-Host "========================================" -ForegroundColor Blue
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
    # irm | iex로 실행되면 exit가 사용자 PowerShell 창을 닫아 안내를 못 읽는다. throw는 창을 남긴다.
    throw $Message
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

# A command name alone does not prove Node is usable (stale Scoop shims exist).
function Get-NodeVersion {
    param([string]$CommandPath)
    if ([string]::IsNullOrWhiteSpace($CommandPath)) { return $null }
    $check = & {
        param($candidate)
        $ErrorActionPreference = 'Continue'
        try {
            $output = (& $candidate --version 2>&1) -join ""
            $code = $LASTEXITCODE
        }
        catch { return $null }
        if ($code -eq 0 -and $output.Trim() -match '^v\d+\.\d+\.\d+$') { return $output.Trim() }
    } $CommandPath
    return $check
}

function Find-UsableNode {
    $candidates = @()
    $command = Get-Command node -CommandType Application -ErrorAction SilentlyContinue
    if ($command) { $candidates += $command.Source }
    $roots = @($env:SCOOP, (Join-Path $env:USERPROFILE 'scoop'), $env:SCOOP_GLOBAL)
    if ($env:ProgramData) { $roots += Join-Path $env:ProgramData 'scoop' }
    foreach ($root in ($roots | Where-Object { $_ } | Select-Object -Unique)) {
        foreach ($app in 'nodejs', 'nodejs-lts') {
            $candidates += Join-Path $root "apps\$app\current\node.exe"
        }
    }
    foreach ($root in @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:LOCALAPPDATA) | Where-Object { $_ }) {
        $candidates += Join-Path $root 'nodejs\node.exe'
    }
    foreach ($path in ($candidates | Select-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
        $version = Get-NodeVersion $path
        if ($version) { return [PSCustomObject]@{ Path = $path; Version = $version } }
    }
    return $null
}

# Keep Scoop's original messages instead of replacing them with 'node not found'.
function Invoke-ScoopApp {
    param([ValidateSet('install', 'reset')][string]$Action, [ValidateSet('nodejs', 'git')][string]$App = 'nodejs')
    $lines = New-Object 'System.Collections.Generic.List[string]'
    $code = & {
        $ErrorActionPreference = 'Continue'
        $savedExitCode = $global:LASTEXITCODE
        $global:LASTEXITCODE = 0
        try {
            & scoop $Action $App *>&1 | ForEach-Object {
                $text = [string]$_
                $lines.Add($text)
                Write-Host $text
            }
            return $global:LASTEXITCODE
        }
        catch {
            $lines.Add($_.Exception.Message)
            return 1
        }
        finally { $global:LASTEXITCODE = $savedExitCode }
    }
    return [PSCustomObject]@{ ExitCode = $code; Output = ($lines -join "`n") }
}

# Official ZIPs need only Windows' built-in ZIP extraction, not Scoop's 7zip dependency.
function Install-OfficialNode {
    $architecture = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
    $arch = switch ($architecture) { 'ARM64' { 'arm64' } 'AMD64' { 'x64' } 'x86' { 'x86' } default { throw "Unsupported Node architecture: $architecture" } }
    $releases = Invoke-RestMethod 'https://nodejs.org/dist/index.json' -TimeoutSec 30
    $release = $releases | Where-Object { $_.lts -and $_.files -contains "win-$arch-zip" } | Select-Object -First 1
    if (-not $release -or $release.version -notmatch '^v\d+\.\d+\.\d+$') { throw 'No supported official Node LTS release found.' }
    $name = "node-$($release.version)-win-$arch"
    $base = "https://nodejs.org/dist/$($release.version)"
    $checksums = (Invoke-WebRequest "$base/SHASUMS256.txt" -UseBasicParsing -TimeoutSec 30).Content
    $match = [regex]::Match([string]$checksums, ('(?m)^([a-fA-F0-9]{64})\s+\*?' + [regex]::Escape("$name.zip") + '\r?$'))
    if (-not $match.Success) { throw 'Official Node ZIP checksum is missing.' }
    $stage = Join-Path $env:TEMP ('claude-node-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $stage | Out-Null
    try {
        $zip = Join-Path $stage "$name.zip"
        Invoke-WebRequest "$base/$name.zip" -OutFile $zip -UseBasicParsing -TimeoutSec 120
        if ((Get-FileHash $zip -Algorithm SHA256).Hash -ne $match.Groups[1].Value) { throw 'Official Node ZIP checksum mismatch; nothing was installed.' }
        Expand-Archive -LiteralPath $zip -DestinationPath $stage
        $extracted = Join-Path $stage $name
        $version = Get-NodeVersion (Join-Path $extracted 'node.exe')
        if ($version -ne $release.version) { throw 'Official Node executable failed version verification.' }
        $parent = Join-Path $env:LOCALAPPDATA 'Programs\CloseAI\Node'
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
        $destination = Join-Path $parent $name
        if (Test-Path -LiteralPath $destination) {
            # Keep an existing installation intact, including any user-added files.
            $destination += '-' + [guid]::NewGuid().ToString('N').Substring(0, 8)
        }
        Move-Item -LiteralPath $extracted -Destination $destination
        return [PSCustomObject]@{ Path = (Join-Path $destination 'node.exe'); Version = $version }
    }
    finally { Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue }
}

function Ensure-Node {
    Refresh-Path
    $node = Find-UsableNode
    if ($node) {
        Add-UserPathEntry (Split-Path $node.Path -Parent)
        Write-Skip "Node.js $($node.Version)"
        return $node.Version
    }
    Write-Host "  Node.js를 설치합니다..."
    $install = Invoke-ScoopApp install
    Refresh-Path
    $node = Find-UsableNode
    $repair = $null
    if (-not $node) {
        # Scoop may say 'already installed' even when current/shims are missing.
        Write-Host '  Node.js 실행 경로를 복구합니다...'
        $repair = Invoke-ScoopApp reset
        Refresh-Path
        $node = Find-UsableNode
    }
    $officialError = $null
    if (-not $node) {
        Write-Host '  Scoop 대신 Node 공식 배포본으로 설치합니다 (관리자 권한 불필요)...'
        try { $node = Install-OfficialNode }
        catch { $officialError = $_.Exception.Message }
    }
    if (-not $node) {
        $details = "Official Node: $officialError / Scoop install exit=$($install.ExitCode): $($install.Output)"
        if ($repair) { $details += " / reset exit=$($repair.ExitCode): $($repair.Output)" }
        $details = $details -replace '\x1B\[[0-?]*[ -/]*[@-~]', ''
        $details = ($details -replace '\s+', ' ').Trim()
        if ($details.Length -gt 600) { $details = $details.Substring(0, 600) }
        Write-Fail "Node.js 실행 확인 실패. 설치 또는 경로 복구가 끝나지 않았습니다. $details"
    }
    Add-UserPathEntry (Split-Path $node.Path -Parent)
    $command = Get-Command node -CommandType Application -ErrorAction SilentlyContinue
    if (-not $command -or -not (Get-NodeVersion $command.Source)) {
        Write-Fail 'Node.js 파일은 있지만 node 명령의 실행 경로 등록을 확인하지 못했습니다.'
    }
    Write-Ok "Node.js $($node.Version) 설치 및 실행 확인"
    return $node.Version
}

function Find-UsableGit {
    $paths = @()
    $command = Get-Command git -CommandType Application -ErrorAction SilentlyContinue
    if ($command) { $paths += $command.Source }
    foreach ($root in @($env:ProgramFiles, ${env:ProgramFiles(x86)}) | Where-Object { $_ }) {
        $paths += Join-Path $root 'Git\cmd\git.exe'
    }
    $paths += Join-Path $env:LOCALAPPDATA 'Programs\Git\cmd\git.exe'
    foreach ($root in @($env:SCOOP, (Join-Path $env:USERPROFILE 'scoop'), $env:SCOOP_GLOBAL) | Where-Object { $_ }) {
        $paths += Join-Path $root 'apps\git\current\cmd\git.exe'
    }
    foreach ($path in ($paths | Select-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
        $version = & {
            $ErrorActionPreference = 'Continue'
            try {
                $text = (& $path --version 2>&1) -join ''
                if ($LASTEXITCODE -eq 0 -and $text -match '^git version \d+\.') { return $text.Trim() }
            } catch { }
        }
        if ($version) { return [PSCustomObject]@{ Path = $path; Version = $version } }
    }
    return $null
}

function Ensure-Git {
    Refresh-Path
    $git = Find-UsableGit
    if ($git) { Add-UserPathEntry (Split-Path $git.Path -Parent); Write-Skip $git.Version; return $git.Version }
    $result = Invoke-ScoopApp install git
    Refresh-Path
    $git = Find-UsableGit
    $wingetCode = 'not available'
    if (-not $git -and (Test-Command winget)) {
        Write-Host '  Scoop 대신 WinGet으로 Git을 사용자 계정에 설치합니다...'
        $wingetCode = & {
            $ErrorActionPreference = 'Continue'
            try {
                & winget install --id Git.Git -e --source winget --scope user --silent --disable-interactivity --accept-package-agreements --accept-source-agreements *>&1 | ForEach-Object { Write-Host ([string]$_) }
                return $global:LASTEXITCODE
            }
            catch { Write-Host $_.Exception.Message; return 1 }
        }
        Refresh-Path
        $git = Find-UsableGit
    }
    if (-not $git) {
        Write-Fail "Git 실행 확인 실패. Scoop exit=$($result.ExitCode): $($result.Output) / WinGet exit=$wingetCode"
    }
    Add-UserPathEntry (Split-Path $git.Path -Parent)
    Write-Ok "$($git.Version) 설치 및 실행 확인"
    return $git.Version
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

# 어떤 이유로 끊겨도 경과 표시를 멈추고 호출한 창의 설정을 돌려놓는다. 들여쓰기는 바꾸지 않는다.
try {

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

$nodeVer = Ensure-Node

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

$gitVer = Ensure-Git

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
    if (Test-Command "winget") {
        & winget install --id Microsoft.WindowsTerminal -e --source winget --accept-package-agreements --accept-source-agreements --disable-interactivity
        if ($LASTEXITCODE -ne 0) { Write-Fail "Windows Terminal 설치에 실패했습니다. 위 오류를 확인하세요." }
    } else {
        Write-Host "  winget이 없어 기존 Scoop으로 공식 Windows Terminal 포터블 배포본을 설치합니다."
        Write-Host "  기존 터미널 설정 파일을 복사하거나 덮어쓰지 않습니다."
        scoop bucket add extras
        scoop install extras/windows-terminal
    }
    Refresh-Path
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
Stop-StepHeartbeat
Write-Host "  확인 완료 [■■■■■■■] 7/7 · 걸린 시간 $([int]$script:installStopwatch.Elapsed.TotalSeconds)초"

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
Write-Host "========================================" -ForegroundColor Blue
Write-Host "  ✅ 설치가 모두 완료되었습니다!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Blue

Write-Host ""
Write-Host "  다음 단계:" -ForegroundColor White
Write-Host "  새 Windows Terminal을 열고 " -NoNewline
Write-Host "claude" -ForegroundColor Yellow -NoNewline
Write-Host " 를 입력하세요."
Write-Host "  처음 실행하면 영어 화면이 몇 개 나옵니다. 로그인 방법은 1번을 고르세요."
Write-Host '  "Quick safety check"에서는 그대로 Enter를 누르면 꺼지니, 아래 화살표로 Yes를 고른 뒤 Enter를 누르세요.'
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

}
catch {
    Stop-StepHeartbeat
    Write-FailureReport -Message $_.Exception.Message
    throw "설치를 중단했습니다. 위의 실패 보고를 설치 도우미에 붙여넣어 주세요."
}
finally {
    Stop-StepHeartbeat
    $ProgressPreference = $savedProgressPreference
}
