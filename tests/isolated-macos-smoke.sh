#!/bin/bash
# Run only inside a disposable macOS VM. Never reset the host user's tools.
set -euo pipefail
if [[ "${CLAUDE_SETUP_DISPOSABLE_VM:-}" != "1" ]] ||
   [[ "$(sysctl -n hw.model)" != VirtualMac* ]]; then
  echo 'Refusing to run: requires a marked disposable macOS VM.' >&2
  exit 1
fi
repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
evidence_dir="$repo_dir/evidence"
mkdir -p "$evidence_dir"
sw_vers > "$evidence_dir/os.txt"
sysctl -n hw.model >> "$evidence_dir/os.txt"

# Seed user-owned preferences before installation and require exact preservation.
defaults write com.googlecode.iterm2 ClaudeSetupPreservationProbe -string 'keep-my-settings'
defaults write com.apple.Terminal ClaudeSetupPreservationProbe -string 'keep-my-settings'
defaults export com.googlecode.iterm2 "$evidence_dir/iterm-before.plist"
defaults export com.apple.Terminal "$evidence_dir/terminal-before.plist"
mkdir -p "$HOME/.claude"
printf '%s\n' '{"permissions":{"deny":["Read(secret)"]},"statusLine":{"type":"command","command":"echo existing-status-line"}}' > "$HOME/.claude/settings.json"

# Allocate a real PTY so the in-progress display is exercised as a user sees it.
set +e
/usr/bin/script -q "$evidence_dir/first-install.log" /bin/bash -c '
  /bin/bash "$1"
  result=$?
  printf "%s\n" "$result" > "$2"
  exit "$result"
' smoke "$repo_dir/install.sh" "$evidence_dir/first-install.exit"
set -e
first_status=$(cat "$evidence_dir/first-install.exit")
if [[ $first_status -ne 0 ]]; then exit "$first_status"; fi

defaults export com.googlecode.iterm2 "$evidence_dir/iterm-after.plist"
defaults export com.apple.Terminal "$evidence_dir/terminal-after.plist"
cmp "$evidence_dir/iterm-before.plist" "$evidence_dir/iterm-after.plist"
cmp "$evidence_dir/terminal-before.plist" "$evidence_dir/terminal-after.plist"

/bin/bash "$repo_dir/install.sh" > "$evidence_dir/reinstall.log" 2>&1
# A malformed settings file must fail rather than erase user settings or report success.
cp "$HOME/.claude/settings.json" "$evidence_dir/settings-good.json"
printf '%s' '{broken' > "$HOME/.claude/settings.json"
set +e
/bin/bash "$repo_dir/install.sh" > "$evidence_dir/invalid-settings.log" 2>&1
invalid_status=$?
set -e
[[ $invalid_status -ne 0 ]]
[[ "$(cat "$HOME/.claude/settings.json")" == '{broken' ]]
if /usr/bin/grep -q '설치가 모두 완료되었습니다' "$evidence_dir/invalid-settings.log"; then
  echo 'Malformed settings were reported as success' >&2
  exit 1
fi
cp "$evidence_dir/settings-good.json" "$HOME/.claude/settings.json"
/bin/zsh -lic 'command -v claude; claude --version; node --version; python3 --version; git --version' > "$evidence_dir/fresh-shell.log" 2>&1
test_node=$(/bin/zsh -lic 'command -v node')
"$test_node" --test "$repo_dir/tests/usage-mode.test.mjs" > "$evidence_dir/usage-mode-tests.log" 2>&1
"$test_node" --input-type=module - "$HOME/.claude" > "$evidence_dir/mode-output.txt" <<'NODE'
import { readFileSync } from 'node:fs'
import { spawnSync } from 'node:child_process'
import assert from 'node:assert/strict'
const settings = JSON.parse(readFileSync(process.argv[2] + '/settings.json', 'utf8'))
assert.deepEqual(settings.permissions, { deny: ['Read(secret)'] })
const run = spawnSync(settings.statusLine.command, { shell: true, encoding: 'utf8', input: JSON.stringify({ context_window: { used_percentage: 37 }, rate_limits: { five_hour: { used_percentage: 17 }, seven_day: { used_percentage: 25 } } }) })
assert.equal(run.status, 0)
assert.match(run.stdout, /existing-status-line/)
assert.match(run.stdout, /37%/)
assert.match(run.stdout, /17%/)
console.log(run.stdout)
NODE

iterm_app="$HOME/Applications/iTerm.app"
if [[ ! -d "$iterm_app" ]]; then iterm_app=/Applications/iTerm.app; fi
open "$iterm_app"
sleep 5
pgrep -x iTerm2 > "$evidence_dir/iterm-pid.txt"
defaults read com.googlecode.iterm2 ClaudeSetupPreservationProbe > "$evidence_dir/preference-probe.txt"
echo 'Disposable macOS install, reinstall, settings preservation, fresh shell, mode and iTerm launch: PASS'
echo 'Account login, actual quota and news response remain untested.'
