#Requires -Version 5.1
# Real Node official download, SHA256 validation, user install, and new-process execution.
$ErrorActionPreference = 'Stop'
$source = [IO.File]::ReadAllText((Join-Path (Split-Path $PSScriptRoot -Parent) 'install.ps1'), [Text.Encoding]::UTF8)
$ast = [Management.Automation.Language.Parser]::ParseInput($source, [ref]$null, [ref]$null)
foreach ($name in 'Get-NodeVersion', 'Install-OfficialNode') {
    $fn = $ast.Find({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name }, $true)
    . ([scriptblock]::Create($fn.Extent.Text))
}
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$node = Install-OfficialNode
if (-not $node.Path.StartsWith((Join-Path $env:LOCALAPPDATA 'Programs\CloseAI\Node'))) { throw 'Node was not installed in the user folder.' }
if ((Get-NodeVersion $node.Path) -ne $node.Version) { throw 'Installed binary did not pass verification.' }
$result = & $node.Path -p '1+1'
if ($LASTEXITCODE -ne 0 -or $result -ne '2') { throw 'Installed Node could not execute JavaScript.' }
# A corrupted archive must be rejected before extraction or installation.
$realDownload = Get-Command Invoke-WebRequest
function Invoke-WebRequest {
    param($Uri, $OutFile, [switch]$UseBasicParsing, $TimeoutSec)
    if ($OutFile) { [IO.File]::WriteAllText($OutFile, 'CORRUPT_ZIP'); return }
    & $realDownload -Uri $Uri -UseBasicParsing -TimeoutSec $TimeoutSec
}
$rejected = $false
try { Install-OfficialNode } catch { $rejected = $_.Exception.Message -match 'checksum mismatch' }
if (-not $rejected) { throw 'Corrupted official download was not rejected.' }
Write-Host 'node-official-tests: OK (real download and corrupt-archive rejection)'
