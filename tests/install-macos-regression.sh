#!/bin/bash

set -euo pipefail

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
test_home=$(mktemp -d "${TMPDIR:-/tmp}/claude-setup-regression.XXXXXX")

cleanup() {
  case "$test_home" in
    "${TMPDIR:-/tmp}"/claude-setup-regression.*) rm -rf -- "$test_home" ;;
  esac
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
