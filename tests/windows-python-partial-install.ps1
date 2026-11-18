#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
Remove-Item Env:CI -ErrorAction SilentlyContinue
$env:PATH = [Environment]::GetEnvironmentVariable('PATH','User') + ';' + [Environment]::GetEnvironmentVariable('PATH','Machine')
$env:CLAUDE_SETUP_REF = $env:GITHUB_SHA
$source = [IO.File]::ReadAllText("$PWD\install.ps1")
$ast = [Management.Automation.Language.Parser]::ParseInput($source,[ref]$null,[ref]$null)
$fn = $ast.Find({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Install-OptionalPython' }, $true)
$source = $source.Replace($fn.Extent.Text, "function Install-OptionalPython { return @{ Detail = 'PYTHON-TEST-FAILURE' } }")
$out = Invoke-Expression $source *>&1 | Out-String -Width 240
if ($out -notmatch 'PYTHON-TEST-FAILURE' -or $out -notmatch 'Claude 사용 준비 완료' -or $out -match '설치가 모두 완료되었습니다') {
    throw "Unexpected partial-install summary: $out"
}
$version = claude --version
if ($LASTEXITCODE -ne 0 -or $version -notmatch 'Claude Code') { throw "Claude failed: $version" }
