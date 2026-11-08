#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$source = [IO.File]::ReadAllText((Join-Path (Split-Path $PSScriptRoot -Parent) 'install.ps1'), [Text.Encoding]::UTF8)
$errors = $null
$ast = [Management.Automation.Language.Parser]::ParseInput($source, [ref]$null, [ref]$errors)
if ($errors) { throw ($errors.Message -join '; ') }
foreach ($name in 'Find-UsableGit', 'Ensure-Git') {
    $fn = $ast.Find({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name }, $true)
    . ([scriptblock]::Create($fn.Extent.Text))
}
function Check($name, [bool]$ok) { if (-not $ok) { throw "FAIL $name" }; Write-Host "PASS $name" }
function Refresh-Path { }
function Add-UserPathEntry($Path) { $script:addedPath = $Path; $env:Path = "$Path;$env:Path" }
function Write-Skip($Message) { Write-Host $Message }
function Write-Ok($Message) { Write-Host $Message }
function Write-Fail($Message) { throw $Message }
$saved = $env:Path
try {
    $env:Path = "$env:WINDIR\System32;$env:WINDIR"
    $git = Find-UsableGit
    Check 'real Git can be recovered outside PATH' ($null -ne $git -and $git.Version -match '^git version')
    function Invoke-ScoopApp($Action, $App) { throw 'Should not reinstall working Git' }
    Check 'working Git repairs PATH without reinstalling' ((Ensure-Git) -eq $git.Version -and $script:addedPath -eq (Split-Path $git.Path -Parent))
    $script:findCalls = 0
    function Find-UsableGit { $script:findCalls++; if ($script:findCalls -ge 3) { return $git }; return $null }
    function Invoke-ScoopApp($Action, $App) { Check 'Scoop targets only Git' ($Action -eq 'install' -and $App -eq 'git'); return [PSCustomObject]@{ ExitCode = 1; Output = '7zip download failed' } }
    function Test-Command($Command) { return $Command -eq 'winget' }
    function winget { $script:wingetArgs = $args -join ' '; $global:LASTEXITCODE = 0 }
    Check 'failed Scoop installation falls back and re-verifies Git' ((Ensure-Git) -eq $git.Version)
    Check 'WinGet is user-scoped and noninteractive' ($script:wingetArgs -match '--scope user' -and $script:wingetArgs -match '--disable-interactivity' -and $script:wingetArgs -match 'Git.Git')
    function Find-UsableGit { return $null }
    function winget { $global:LASTEXITCODE = 9 }
    $failure = ''
    try { Ensure-Git } catch { $failure = $_.Exception.Message }
    Check 'both failed installers retain useful evidence' ($failure -match '7zip download failed' -and $failure -match 'WinGet exit=9')
}
finally { $env:Path = $saved }
Write-Host 'git-recovery-tests: OK'
