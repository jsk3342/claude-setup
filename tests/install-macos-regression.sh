#!/bin/bash

set -euo pipefail

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
test_home=$(mktemp -d "${TMPDIR:-/tmp}/claude-setup-regression.XXXXXX")
tool_home=$(mktemp -d "${TMPDIR:-/tmp}/claude-setup-tools.XXXXXX")

cleanup() {
  for target in "$test_home" "$tool_home"; do
    case "$target" in
      "${TMPDIR:-/tmp}"/claude-setup-regression.*|"${TMPDIR:-/tmp}"/claude-setup-tools.*)
        rm -rf -- "$target"
        ;;
    esac
  done
}
trap cleanup EXIT

sudo() { return 0; }
xcode-select() { return 0; }
sw_vers() { printf '%s\n' "14.0"; }
uname() { printf '%s\n' "arm64"; }
brew() {
  if [[ "${1:-}" == "--version" ]]; then
    printf '%s\n' "Homebrew 4.6.0"
  fi
  return 0
}
node() { printf '%s\n' "v22.0.0"; }
python3() { printf '%s\n' "Python 3.13.0"; }
git() { printf '%s\n' "git version 2.50.0"; }
claude() { printf '%s\n' "2.1.212 (Claude Code)"; }
curl() { return 22; }
sleep() { return 0; }
kill() { return 1; }
export -f sudo xcode-select sw_vers uname brew node python3 git claude curl sleep kill

set +e
install_output=$(HOME="$test_home" SHELL=/bin/bash /bin/bash "$repo_dir/install.sh" 2>&1)
install_status=$?
set -e

if [[ $install_status -eq 0 ]] || [[ "$install_output" == *"설치가 모두 완료되었습니다"* ]]; then
  printf '%s\n' "$install_output"
  printf '%s\n' "FAIL: a process-only claude command produced a completion banner" >&2
  exit 1
fi
if [[ "$install_output" != *"Claude Code를 설치합니다"* ]]; then
  printf '%s\n' "$install_output"
  printf '%s\n' "FAIL: a process-only claude command did not trigger repair" >&2
  exit 1
fi

if grep -Fq 'xcode-select --install' "$repo_dir/install.sh"; then
  printf '%s\n' "FAIL: the installer still owns the Homebrew CLT installation flow" >&2
  exit 1
fi

tool_bin="$tool_home/bin"
mkdir -p "$tool_home/.local/bin" "$tool_bin"

cat > "$tool_home/.local/bin/claude" <<'SCRIPT'
#!/bin/bash
printf '%s\n' "2.1.212 (Claude Code)"
SCRIPT

cat > "$tool_bin/brew" <<'SCRIPT'
#!/bin/bash
fake_bin=$(cd "$(dirname "$0")" && pwd)
case "${1:-}" in
  --version)
    printf '%s\n' "Homebrew 4.6.0"
    ;;
  shellenv)
    printf 'export PATH="%s:$PATH"\n' "$fake_bin"
    ;;
  install)
    if [[ "${2:-}" == "node" && "${FAKE_BREW_FAIL_NODE:-0}" == "1" ]]; then
      exit 42
    fi
    exit 64
    ;;
  *)
    exit 64
    ;;
esac
SCRIPT

cat > "$tool_bin/node" <<'SCRIPT'
#!/bin/bash
printf '%s\n' "v22.0.0"
SCRIPT

cat > "$tool_bin/python3" <<'SCRIPT'
#!/bin/bash
printf '%s\n' "Python 3.13.0"
SCRIPT

cat > "$tool_bin/git" <<'SCRIPT'
#!/bin/bash
printf '%s\n' "git version 2.50.0"
SCRIPT

chmod +x "$tool_home/.local/bin/claude" "$tool_bin/brew" "$tool_bin/node" "$tool_bin/python3" "$tool_bin/git"

set +e
tool_output=$(
  unset -f sudo xcode-select brew node python3 git claude curl sleep kill
  HOME="$tool_home" SHELL=/bin/bash PATH="$tool_bin:/usr/bin:/bin:/usr/sbin:/sbin" /bin/bash "$repo_dir/install.sh" 2>&1
)
tool_status=$?
set -e

if [[ $tool_status -ne 0 ]] || [[ "$tool_output" != *"설치가 모두 완료되었습니다"* ]]; then
  printf '%s\n' "$tool_output"
  printf '%s\n' "FAIL: a verified base toolchain did not complete successfully" >&2
  exit 1
fi

rm -f "$tool_bin/node"
set +e
partial_output=$(
  unset -f sudo xcode-select brew node python3 git claude curl sleep kill
  HOME="$tool_home" SHELL=/bin/bash PATH="$tool_bin:/usr/bin:/bin:/usr/sbin:/sbin" FAKE_BREW_FAIL_NODE=1 /bin/bash "$repo_dir/install.sh" 2>&1
)
partial_status=$?
set -e

if [[ $partial_status -eq 0 ]] || [[ "$partial_output" == *"설치가 모두 완료되었습니다"* ]]; then
  printf '%s\n' "$partial_output"
  printf '%s\n' "FAIL: a missing Node.js install was reported as full success" >&2
  exit 1
fi
if [[ "$partial_output" != *"Node.js: Homebrew 설치 또는 실행 확인에 실패했습니다"* ]]; then
  printf '%s\n' "$partial_output"
  printf '%s\n' "FAIL: the Node.js failure was not included in the final result" >&2
  exit 1
fi

path_line=$(sed -n "s/^  local path_line='\(.*\)'$/\1/p" "$repo_dir/install.sh")
if [[ -z "$path_line" ]]; then
  printf '%s\n' "FAIL: could not find the persistent PATH line" >&2
  exit 1
fi

(
  HOME="$test_home"
  PATH="$HOME/conflict:$HOME/.local/bin:/usr/bin:/bin"
  eval "$path_line"
  case "$PATH" in
    "$HOME/.local/bin"|"$HOME/.local/bin":*) ;;
    *)
      printf '%s\n' "FAIL: ~/.local/bin was not moved to the front of PATH" >&2
      exit 1
      ;;
  esac
)

printf '%s\n' "macOS installer regressions: OK"
