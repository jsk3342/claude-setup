#Requires -Version 5.1
# Isolated recovery tests: real Node executable, no persistent PATH edits.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$source = [IO.File]::ReadAllText((Join-Path (Split-Path $PSScriptRoot -Parent) 'install.ps1'), [Text.Encoding]::UTF8)
$parseErrors = $null
$ast = [Management.Automation.Language.Parser]::ParseInput($source, [ref]$null, [ref]$parseErrors)
if ($parseErrors) { throw ($parseErrors.Message -join '; ') }
foreach ($name in 'Get-NodeVersion', 'Find-UsableNode', 'Invoke-NodeScoop', 'Ensure-Node') {
    $fn = $ast.Find({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name }, $true)
    . ([scriptblock]::Create($fn.Extent.Text))
}
function Check($name, [bool]$ok) { if (-not $ok) { throw "FAIL $name" }; Write-Host "PASS $name" }
$realNode = (Get-Command node -CommandType Application).Source
$realVersion = Get-NodeVersion $realNode
Check 'actual Node version is verified' ($realVersion -match '^v\d+\.\d+\.\d+$')
$work = Join-Path $env:TEMP ('node recovery ' + [char]0xD55C + [guid]::NewGuid().ToString('N'))
$nodeDir = Join-Path $work 'apps\nodejs\current'
New-Item -ItemType Directory -Force -Path $nodeDir | Out-Null
$testNode = Join-Path $nodeDir 'node.exe'
Copy-Item $realNode $testNode
$savedPath = $env:Path
$savedScoop = $env:SCOOP
try {
    # Node exists in a custom Scoop root but its shim/PATH entry is gone.
    $env:SCOOP = $work
    $env:Path = "$env:WINDIR\System32;$env:WINDIR"
    $found = Find-UsableNode
    Check 'custom Scoop root recovers a real binary without a shim' ($found.Path -eq $testNode -and $found.Version -eq $realVersion)
    function Refresh-Path { }
    function Add-UserPathEntry($Path) { $script:addedPath = $Path; $env:Path = "$Path;$env:Path" }
    function Write-Skip($Message) { Write-Host $Message }
    function Write-Ok($Message) { Write-Host $Message }
    function Write-Fail($Message) { throw $Message }
    function Invoke-NodeScoop($Action) { throw 'Should not install an already usable Node' }
    $version = Ensure-Node
    Check 'existing binary repairs PATH and runs by name' ($version -eq $realVersion -and $script:addedPath -eq $nodeDir -and (& node --version) -eq $realVersion)

    # A stale shim can exist while its target is missing.
    $bad = Join-Path $work 'broken.cmd'
    Set-Content $bad '@exit /b 7' -Encoding Ascii
    Check 'a broken native command is rejected' ($null -eq (Get-NodeVersion $bad))

    # Ensure-Node must verify after installing, not trust a command/exit code alone.
    $script:findCalls = 0
    $script:actions = @()
    function Find-UsableNode {
        $script:findCalls++
        if ($script:findCalls -ge 2) { return [PSCustomObject]@{ Path = $testNode; Version = $realVersion } }
        return $null
    }
    function Invoke-NodeScoop($Action) { $script:actions += $Action; return [PSCustomObject]@{ ExitCode = 0; Output = 'installed' } }
    Check 'fresh installation verifies the executable' ((Ensure-Node) -eq $realVersion -and ($script:actions -join ',') -eq 'install')

    $script:findCalls = 0
    $script:actions = @()
    function Find-UsableNode {
        $script:findCalls++
        if ($script:findCalls -ge 3) { return [PSCustomObject]@{ Path = $testNode; Version = $realVersion } }
        return $null
    }
    Check 'already-installed but unlinked Node gets a targeted reset' ((Ensure-Node) -eq $realVersion -and ($script:actions -join ',') -eq 'install,reset')

    function Find-UsableNode { return $null }
    function Invoke-NodeScoop($Action) { return [PSCustomObject]@{ ExitCode = 23; Output = 'DOWNLOAD_FAILED original cause' } }
    function Install-OfficialNode { throw 'OFFICIAL_DOWNLOAD_FAILED' }
    $errorText = ''
    try { Ensure-Node } catch { $errorText = $_.Exception.Message }
    Check 'failure preserves Scoop cause and exit status' ($errorText -match 'DOWNLOAD_FAILED' -and $errorText -match 'exit=23')

    function Install-OfficialNode { return [PSCustomObject]@{ Path = $testNode; Version = $realVersion } }
    Check 'official fallback recovers when Scoop fails' ((Ensure-Node) -eq $realVersion)

    # Real capture path with native stderr and a failed exit, under PS 5.1 Stop.
    $fn = $ast.Find({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Invoke-NodeScoop' }, $true)
    . ([scriptblock]::Create($fn.Extent.Text))
    Set-Content (Join-Path $work 'scoop.cmd') '@echo ORIGINAL_STDERR 1>&2
@exit /b 17'.Replace('\r\n', "`r`n") -Encoding Ascii
    $env:Path = "$work;$env:Path"
    $captured = Invoke-NodeScoop install
    Check 'native stderr does not erase failure details' ($captured.ExitCode -eq 17 -and $captured.Output -match 'ORIGINAL_STDERR')
}
finally { $env:Path = $savedPath; $env:SCOOP = $savedScoop; Remove-Item $work -Recurse -Force }
Write-Host 'node-recovery-tests: OK'
