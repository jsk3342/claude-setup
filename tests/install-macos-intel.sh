#!/bin/bash
# Intel Mac without Homebrew: the official Homebrew installer refuses x86_64 since
# 2026-09, so Node.js, Git, Python 3 and iTerm2 must come from official installers.
# Downloads from nodejs.org and iterm2.com are real (pinned checksums are checked);
# sudo, installer, softwareupdate and xcode-select are fakes.

set -euo pipefail

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/claude-setup-intel.XXXXXX")
cache_dir="${CLAUDE_SETUP_TEST_CACHE:-${TMPDIR:-/tmp}/claude-setup-intel-cache}"
mkdir -p "$cache_dir"

cleanup() {
  case "$work" in
    "${TMPDIR:-/tmp}"/claude-setup-intel.*) rm -rf -- "$work" ;;
  esac
}
trap cleanup EXIT

hide_host_tools='(version 1)(allow default)(deny file-read* file-read-metadata file-test-existence (subpath "/opt/homebrew") (subpath "/usr/local/Homebrew") (literal "/usr/local/bin/brew") (literal "/usr/local/bin/node") (subpath "/Applications/iTerm.app"))'

make_fakes() {
  local bin="$1" arch="$2"
  mkdir -p "$bin"

  cat > "$bin/uname" <<SCRIPT
#!/bin/bash
[[ "\${1:-}" == "-m" ]] && { echo "$arch"; exit 0; }
exec /usr/bin/uname "\$@"
SCRIPT

  cat > "$bin/sysctl" <<SCRIPT
#!/bin/bash
if [[ "\$*" == "-n hw.optional.arm64" ]]; then
  [[ "$arch" == "arm64" ]] && echo 1 || echo 0
  exit 0
fi
exec /usr/sbin/sysctl "\$@"
SCRIPT

  cat > "$bin/sw_vers" <<'SCRIPT'
#!/bin/bash
echo "${FAKE_MACOS:-14.5}"
SCRIPT

  cat > "$bin/sudo" <<'SCRIPT'
#!/bin/bash
[[ "${1:-}" == "-v" ]] && exit 0
case "${1:-}" in
  touch|rm) exit 0 ;;
esac
exec "$@"
SCRIPT

  # Real network for the two official download hosts, cached across runs.
  cat > "$bin/curl" <<SCRIPT
#!/bin/bash
url="" out=""
while [[ \$# -gt 0 ]]; do
  case "\$1" in
    -o) out="\$2"; shift 2 ;;
    -*) shift ;;
    *) url="\$1"; shift ;;
  esac
done
case "\$url" in
  https://nodejs.org/dist/*|https://iterm2.com/downloads/stable/*) ;;
  https://raw.githubusercontent.com/Homebrew/*) echo "Homebrew on macOS is only supported on Apple Silicon processors!" >&2; exit 1 ;;
  *) echo "fake curl: blocked \$url" >&2; exit 22 ;;
esac
echo "\$url" >> "$work/curl.log"
key=\$(printf '%s' "\$url" | /usr/bin/shasum -a 256 | cut -c1-32)
if [[ "\$url" == *SHASUMS256.txt ]]; then
  /usr/bin/curl -fsSL "\$url" -o "$cache_dir/\$key" || exit 22
elif [[ ! -s "$cache_dir/\$key" ]]; then
  /usr/bin/curl -fsSL "\$url" -o "$cache_dir/\$key.part" && mv "$cache_dir/\$key.part" "$cache_dir/\$key" || exit 22
fi
if [[ -n "\$out" ]]; then cp "$cache_dir/\$key" "\$out"; else cat "$cache_dir/\$key"; fi
SCRIPT

  cat > "$bin/installer" <<SCRIPT
#!/bin/bash
[[ "\$1" == "-pkg" && "\$3" == "-target" && "\$4" == "/" ]] || { echo "bad installer args: \$*" >&2; exit 2; }
/usr/sbin/pkgutil --check-signature "\$2" | grep -q "Node.js Foundation" || { echo "unsigned pkg" >&2; exit 3; }
printf '#!/bin/bash\necho v24.0.0-fake\n' > "$bin/node"
chmod +x "$bin/node"
SCRIPT

  cat > "$bin/softwareupdate" <<SCRIPT
#!/bin/bash
echo "softwareupdate \$*" >> "$work/softwareupdate.log"
if [[ "\$1" == "-l" ]]; then
  [[ "\${FAKE_NO_CLT_LABEL:-0}" == "1" ]] && { echo "No new software available."; exit 0; }
  cat <<'LIST'
Software Update Tool

Finding available software
Software Update found the following new or updated software:
* Label: Command Line Tools for Xcode-15.3
	Title: Command Line Tools for Xcode, Version: 15.3, Size: 700000KiB, Recommended: YES,
* Label: Command Line Tools for Xcode-16.2
	Title: Command Line Tools for Xcode, Version: 16.2, Size: 751793KiB, Recommended: YES,
LIST
  exit 0
fi
[[ "\$1" == "-i" && "\$2" == "Command Line Tools for Xcode-16.2" ]] || { echo "unexpected label: \$2" >&2; exit 4; }
touch "$work/clt-installed"
SCRIPT

  cat > "$bin/xcode-select" <<SCRIPT
#!/bin/bash
[[ "\$1" == "--switch" ]] && exit 0
[[ -f "$work/clt-installed" ]] && { echo /Library/Developer/CommandLineTools; exit 0; }
exit 2
SCRIPT

  cat > "$bin/git" <<SCRIPT
#!/bin/bash
[[ -f "$work/clt-installed" ]] || exit 1
echo "git version 2.39.5 (Apple Git-154)"
SCRIPT

  cat > "$bin/python3" <<SCRIPT
#!/bin/bash
[[ -f "$work/clt-installed" ]] || exit 1
echo "Python 3.9.6"
SCRIPT

  chmod +x "$bin"/*
}

run_install() {
  local home="$1" bin="$2"
  shift 2
  mkdir -p "$home/.local/bin"
  printf '#!/bin/bash\necho "2.1.212 (Claude Code)"\n' > "$home/.local/bin/claude"
  chmod +x "$home/.local/bin/claude"
  set +e
  # Hide this host's own Homebrew and Node so the run sees a fresh Mac.
  output=$(sandbox-exec -p "$hide_host_tools" env "$@" HOME="$home" SHELL=/bin/bash TMPDIR="$work" PATH="$bin:/usr/bin:/bin:/usr/sbin:/sbin" /bin/bash "$repo_dir/install.sh" 2>&1)
  status=$?
  set -e
}

fail_with() {
  printf '%s\n' "$output"
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

# ── Intel, no Homebrew: everything installs, full success ──
rm -f "$work/clt-installed" "$work/softwareupdate.log"
make_fakes "$work/intel-bin" x86_64
run_install "$work/intel-home" "$work/intel-bin" FAKE_MACOS=14.5
[[ $status -eq 0 ]] || fail_with "Intel install did not exit 0 (status $status)"
[[ "$output" == *"설치가 모두 완료되었습니다"* ]] || fail_with "Intel install had no completion banner"
[[ "$output" == *"인텔 Mac은 Homebrew 공식 설치기가 더 이상 지원하지 않아 건너뜁니다"* ]] || fail_with "Homebrew step was not skipped on Intel"
[[ "$output" != *"Homebrew를 설치합니다"* ]] || fail_with "Intel install still ran the Homebrew installer"
[[ "$output" == *"Node.js v24.0.0-fake 설치 완료"* ]] || fail_with "Node.js pkg was not installed"
[[ "$output" == *"Python 3.9.6 설치 완료 (macOS 기본 개발 도구)"* ]] || fail_with "Python 3 did not come from Command Line Tools"
# The Python step already installed the Command Line Tools, which also ship Git.
[[ "$output" == *"Apple Git-154) (이미 설치됨, 스킵)"* ]] || fail_with "Git did not come from Command Line Tools"
[[ "$output" == *"Homebrew  인텔 Mac이라 생략"* ]] || fail_with "summary did not explain the skipped Homebrew"
[[ -x "$work/intel-home/Applications/iTerm.app/Contents/MacOS/iTerm2" ]] || fail_with "iTerm2.app was not extracted"
grep -q 'nodejs.org/dist/latest-v24.x/node-v.*\.pkg$' "$work/curl.log" || fail_with "macOS 14.5 did not use the Node 24 pkg"
grep -q 'iTerm2-3_7_6.zip$' "$work/curl.log" || fail_with "macOS 14.5 did not use the iTerm2 3.7.6 zip"
[[ $(grep -c -- '-l' "$work/softwareupdate.log") -eq 1 ]] || fail_with "Command Line Tools were searched more than once"

# ── Intel on macOS 12.3: older Node and iTerm2 lines ──
rm -f "$work/clt-installed" "$work/curl.log"
make_fakes "$work/old-bin" x86_64
run_install "$work/old-home" "$work/old-bin" FAKE_MACOS=12.3
[[ $status -eq 0 ]] || fail_with "macOS 12.3 Intel install did not exit 0 (status $status)"
grep -q 'nodejs.org/dist/latest-v22.x/node-v.*\.pkg$' "$work/curl.log" || fail_with "macOS 12.3 did not use the Node 22 pkg"
grep -q 'iTerm2-3_5_14.zip$' "$work/curl.log" || fail_with "macOS 12.3 did not use the iTerm2 3.5.14 zip"

# ── Intel, Command Line Tools unavailable: honest partial failure ──
rm -f "$work/clt-installed" "$work/softwareupdate.log"
make_fakes "$work/noclt-bin" x86_64
run_install "$work/noclt-home" "$work/noclt-bin" FAKE_MACOS=14.5 FAKE_NO_CLT_LABEL=1
[[ $status -ne 0 ]] || fail_with "missing Command Line Tools still exited 0"
[[ "$output" != *"설치가 모두 완료되었습니다"* ]] || fail_with "missing Command Line Tools still printed the completion banner"
[[ "$output" == *"Python 3: macOS 기본 개발 도구 설치에 실패했습니다"* ]] || fail_with "Python 3 failure was not reported"
[[ "$output" == *"Git: macOS 기본 개발 도구 설치에 실패했습니다"* ]] || fail_with "Git failure was not reported"
[[ $(grep -c -- '-l' "$work/softwareupdate.log") -eq 1 ]] || fail_with "failed Command Line Tools search was retried"

# ── Apple Silicon whose Homebrew install fails: tools still install directly ──
rm -f "$work/clt-installed"
make_fakes "$work/arm-bin" arm64
run_install "$work/arm-home" "$work/arm-bin" FAKE_MACOS=26.0
[[ $status -ne 0 ]] || fail_with "failed Homebrew on Apple Silicon exited 0"
[[ "$output" == *"Homebrew: 설치 후 실행 확인에 실패했습니다"* || "$output" == *"Homebrew: 공식 설치기 실행에 실패했습니다"* ]] || fail_with "Homebrew failure was not reported"
[[ "$output" == *"Node.js v24.0.0-fake 설치 완료"* ]] || fail_with "Node.js was not installed after Homebrew failed"
[[ -x "$work/arm-home/Applications/iTerm.app/Contents/MacOS/iTerm2" ]] || fail_with "iTerm2 was not installed after Homebrew failed"

printf '%s\n' "Intel macOS installer: OK"
