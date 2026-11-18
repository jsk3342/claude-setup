#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$source = [IO.File]::ReadAllText((Join-Path (Split-Path $PSScriptRoot) 'install.ps1'))
$errors = $null
$ast = [Management.Automation.Language.Parser]::ParseInput($source, [ref]$null, [ref]$errors)
if ($errors.Count) { throw ($errors -join ', ') }
foreach ($name in 'Install-OptionalPython','Invoke-ScoopApp','Write-Ok','Write-Skip') {
    $fn = $ast.Find({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name }, $true)
    . ([scriptblock]::Create($fn.Extent.Text))
}
function Refresh-Path {}
function Test-Command($name) { return $name -eq 'winget' -and $scenario -ne 'no-winget' }
function Get-PythonVersion { if ($script:usable) { return 'Python 3.15.2' } }
function scoop($action, $app) {
    if ($app -ne 'python') { throw "Unexpected package $app" }
    if ($action -eq 'list') { 'python    Install failed'; return }
    if ($action -ne 'install') { throw "Unexpected Scoop operation $action" }
    $script:scoopCalls++
    $script:usable = $scenario -eq 'scoop'
    if ($script:usable) { $global:LASTEXITCODE = 0 }
    else { 'sample extraction error'; $global:LASTEXITCODE = 7 }
}
function winget {
    if (($args -join ' ') -notmatch '--id Python\.Python\.3\.15 --exact --source winget --scope user') { throw 'Wrong fallback package or scope' }
    $script:wingetCalls++
    $script:usable = $scenario -eq 'fallback'
    $global:LASTEXITCODE = 0 # A success exit without a runnable Python must still be reported.
}
foreach ($scenario in 'existing','scoop','fallback','both-failed','no-winget') {
    $script:usable = $scenario -eq 'existing'
    $script:scoopCalls = 0
    $script:wingetCalls = 0
    $result = Install-OptionalPython
    if ($scoopCalls -ne [int]($scenario -ne 'existing')) { throw "Unexpected Scoop attempts: $scenario" }
    if ($wingetCalls -ne [int]($scenario -in 'fallback','both-failed')) { throw "Unexpected WinGet attempts: $scenario" }
    if ($scenario -in 'both-failed','no-winget') {
        if ($result.Version -or $result.Detail -notmatch 'Scoop exit=7' -or $result.Detail -notmatch 'Install failed' -or $result.Detail -notmatch 'sample extraction error') { throw "Missing diagnostic: $($result.Detail)" }
    } elseif ($result.Version -ne 'Python 3.15.2') { throw "Expected working Python: $scenario" }
    Write-Host "PASS $scenario"
}
