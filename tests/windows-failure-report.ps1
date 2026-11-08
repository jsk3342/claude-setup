#Requires -Version 5.1
# install.ps1 really failing: the heartbeat, the failure report and what is left behind in the caller's window.
# Node is hidden and a fake scoop "installs" it without producing it, so step 2 stops the installer.
# ASCII only: this file has no BOM, so Korean text is built from code points.
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$script:Failures = 0
function Check($name, [bool]$ok) {
    if ($ok) { Write-Host "PASS  $name" } else { Write-Host "FAIL  $name"; $script:Failures++ }
}
function Korean([int[]]$codes) { -join ($codes | ForEach-Object { [char]$_ }) }

$reportStart = Korean 0xC124,0xCE58,0x20,0xC2E4,0xD328,0x20,0xBCF4,0xACE0,0x20,0xC2DC,0xC791   # install failure report start
$reportEnd   = Korean 0xC124,0xCE58,0x20,0xC2E4,0xD328,0x20,0xBCF4,0xACE0,0x20,0xB05D           # install failure report end
$heartbeat   = Korean 0xACBD,0xACFC,0x20                                                        # elapsed
$secondWord  = Korean 0xAC78,0xB9B0,0x20,0xC2DC,0xAC04,0x3A,0x20                                # time taken:

$Root = Split-Path -Parent $PSScriptRoot
$work = Join-Path $env:RUNNER_TEMP "failure-report-$([guid]::NewGuid().ToString('N'))"
$bin = Join-Path $work 'bin'
New-Item -ItemType Directory -Path $bin | Out-Null

# A fake scoop that takes 20 seconds and leaves no node behind.
Set-Content -Path (Join-Path $bin 'scoop.cmd') -Encoding Ascii -Value "@ping -n 21 127.0.0.1 >nul`r`n@exit /b 0"

# Keep only system folders on PATH, and make the installer's own PATH refresh see the same thing.
$cleanPath = "$bin;$env:WINDIR\System32;$env:WINDIR;$env:WINDIR\System32\WindowsPowerShell\v1.0"
foreach ($scope in 'Machine', 'User') { [Environment]::SetEnvironmentVariable('PATH', $(if ($scope -eq 'User') { $bin } else { "$env:WINDIR\System32;$env:WINDIR;$env:WINDIR\System32\WindowsPowerShell\v1.0" }), $scope) }

$marker = 'CALLER-WINDOW-CONTINUES'
$driver = Join-Path $work 'driver.ps1'
$installer = Join-Path $Root 'install.ps1'
# Same way customers run it: the script text through Invoke-Expression, in a window that stays open.
Set-Content -Path $driver -Encoding Ascii -Value @"
`$ProgressPreference = 'Inquire'
`$text = [IO.File]::ReadAllText('$installer', [Text.Encoding]::UTF8)
# The disposable runner has Node binaries outside PATH too. Force the missing-binary
# scenario here; windows-node-recovery.ps1 exercises the real filesystem discovery.
`$ast = [Management.Automation.Language.Parser]::ParseInput(`$text, [ref]`$null, [ref]`$null)
`$fn = `$ast.Find({ param(`$n) `$n -is [Management.Automation.Language.FunctionDefinitionAst] -and `$n.Name -eq 'Find-UsableNode' }, `$true)
`$text = `$text.Replace(`$fn.Extent.Text, 'function Find-UsableNode { return `$null }; function Install-OfficialNode { throw ''TEST_OFFICIAL_DOWNLOAD_FAILED'' }')
try { Invoke-Expression `$text ; Write-Output 'INSTALLER-RETURNED' }
catch { Write-Output "CAUGHT=`$(`$_.Exception.Message)"; Write-Output 'INSTALLER-THREW' }
Write-Output "PROGRESS-AFTER=`$ProgressPreference"
Write-Output '$marker'
Start-Sleep -Seconds 20
Write-Output 'WINDOW-DONE'
"@

$env:Path = $cleanPath
$out = Join-Path $work 'out.txt'
$err = Join-Path $work 'err.txt'
$p = Start-Process powershell.exe -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$driver`"" -NoNewWindow -PassThru -Wait -RedirectStandardOutput $out -RedirectStandardError $err
$text = [IO.File]::ReadAllText($out, [Text.Encoding]::UTF8) + [IO.File]::ReadAllText($err, [Text.Encoding]::UTF8)
Write-Host '--- installer output'
Write-Host $text
Write-Host '---'

$lines = @($text -split "`r?`n")
$markerAt = [array]::IndexOf($lines, $marker)
$startAt = -1; for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i].Contains($reportStart)) { $startAt = $i; break } }
$endAt = -1; for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i].Contains($reportEnd)) { $endAt = $i; break } }

Check 'installer stopped with an error' ($text -match 'INSTALLER-THREW')
Check 'report block is printed' ($startAt -ge 0 -and $endAt -gt $startAt)
if ($startAt -ge 0 -and $endAt -gt $startAt) {
    $block = ($lines[$startAt..$endAt] -join "`n")
    Check 'report names step 2 Node.js' ($block -match '2/7 Node\.js')
    Check 'report carries the error text' ($block -match 'node')
    Check 'report has time taken in seconds' ($block.Contains($secondWord))
    Check 'report has the OS' ($block -match 'OS: Windows \d')
    Check 'report has the chip' ($block -match 'AMD64|ARM64|x86')
    Check 'report has PowerShell version' ($block -match 'PowerShell: 5\.1')
}
$before = @($lines[0..$(if ($startAt -ge 0) { $startAt } else { $lines.Count - 1 })] | Where-Object { $_.Contains($heartbeat) })
Check 'elapsed line appears during a 20 second step' ($before.Count -ge 1)
Check 'caller window gets its progress setting back' ($text -match 'PROGRESS-AFTER=Inquire')
Check 'window reached the end' ($text -match 'WINDOW-DONE')
if ($markerAt -ge 0) {
    $after = @($lines[($markerAt + 1)..($lines.Count - 1)] | Where-Object { $_.Contains($heartbeat) })
    Check 'no elapsed line after the installer ended' ($after.Count -eq 0)
} else { Check 'marker reached' $false }

# The report itself, with a user folder inside the error text.
$source = [IO.File]::ReadAllText($installer, [Text.Encoding]::UTF8)
$ast = [System.Management.Automation.Language.Parser]::ParseInput($source, [ref]$null, [ref]$null)
$fn = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Write-FailureReport' }, $true)
. ([scriptblock]::Create($fn.Extent.Text))
$script:currentStepLabel = '2/7 test'
$script:installStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$shown = (Write-FailureReport -Message "cannot read $env:USERPROFILE\secret.txt`r`nsecond line") 6>&1 | Out-String
Check 'report hides the user folder' ((-not $shown.Contains($env:USERPROFILE)) -and $shown.Contains('~\secret.txt'))
Check 'report keeps a multi-line error on one line' ($shown -match 'secret\.txt second line')

if ($script:Failures) { throw "$script:Failures failure report test(s) failed." }
Write-Output 'failure-report-tests: OK'
