#!/bin/bash
# ============================================================
# 클로드 코드 올인원 설치 스크립트 (macOS)
# 사용법: /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/jsk3342/claude-setup/main/install.sh)"
# ============================================================

set -e
set -o pipefail

# ── 색상 ──
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color
BOLD='\033[1m'

step=0
total=7
completed=0
step_warnings=0
step_started=0
warnings=()
homebrew_skipped=0
status_monitor_pid=""
cleanup_monitor() {
  if [[ -n "$status_monitor_pid" ]]; then
    kill "$status_monitor_pid" 2>/dev/null || true
    wait "$status_monitor_pid" 2>/dev/null || true
    status_monitor_pid=""
  fi
}
trap cleanup_monitor EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

finish_step() {
  if [[ $step -gt 0 ]]; then
    if [[ ${#warnings[@]} -eq $step_warnings ]]; then
      completed=$((completed + 1))
      echo "  단계 확인 완료 · 경과 $((SECONDS - step_started))초"
    else
      echo "  단계 일부 미완료 · 아래 안내를 확인하세요."
    fi
  fi
}

progress() {
  finish_step
  step=$((step + 1))
  step_warnings=${#warnings[@]}
  step_started=$SECONDS
  local bar="" i
  for ((i=0; i<total; i++)); do
    if [[ $i -lt $completed ]]; then bar+="■"; else bar+="□"; fi
  done
  echo ""
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${BOLD}[$step/$total] $1 · 진행 중${NC}"
  echo "  확인 완료 [$bar] $completed/$total (시간 진행률이 아닙니다)"
  echo "  이유: $2"
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# Foreground commands retain stdin and their own download logs. Only long,
# non-interactive installs get a heartbeat; authentication stays unobstructed.
run_with_status() {
  local result=0 started=$SECONDS
  if [[ -t 1 ]]; then
    (
      while sleep 15; do
        echo "  설치 작업 실행 중 · 경과 $((SECONDS - started))초 · 완료 문구를 기다려주세요."
      done
    ) &
    status_monitor_pid=$!
  fi
  "$@" || result=$?
  cleanup_monitor
  return "$result"
}

ok() {
  echo -e "  ${GREEN}✓${NC} $1"
}

skip() {
  echo -e "  ${YELLOW}→${NC} $1 (이미 설치됨, 스킵)"
}

fail() {
  echo -e "  ${RED}✗${NC} $1"
  exit 1
}

warn() {
  warnings+=("$1")
  echo -e "  ${YELLOW}!${NC} $1"
}

print_warning_summary() {
  if [[ ${#warnings[@]} -eq 0 ]]; then
    return
  fi

  echo ""
  echo -e "${YELLOW}완료되지 않은 항목:${NC}"
  for item in "${warnings[@]}"; do
    echo "  - $item"
  done
}

get_brew_version() {
  local version_output

  if ! version_output=$(brew --version 2>&1); then
    return 1
  fi

  printf '%s\n' "${version_output%%$'\n'*}"
}

ensure_brew_in_path() {
  local brew_bin=""
  local shellenv_output

  if command -v brew &>/dev/null && get_brew_version &>/dev/null; then
    return 0
  fi

  if [[ -x /opt/homebrew/bin/brew ]]; then
    brew_bin=/opt/homebrew/bin/brew
  elif [[ -x /usr/local/bin/brew ]]; then
    brew_bin=/usr/local/bin/brew
  else
    return 1
  fi

  if ! shellenv_output=$("$brew_bin" shellenv 2>/dev/null); then
    return 1
  fi

  eval "$shellenv_output"
  command -v brew &>/dev/null && get_brew_version &>/dev/null
}

# /usr/bin/git and /usr/bin/python3 are stubs until the Command Line Tools exist;
# running them only opens Apple's install popup, so treat them as missing.
is_clt_stub() {
  [[ "$(command -v "$1" 2>/dev/null)" == "/usr/bin/$1" ]] && ! xcode-select -p &>/dev/null
}

# Rosetta shells report x86_64 from uname, so ask the hardware directly.
is_apple_silicon() {
  [[ "$(uname -m)" == "arm64" ]] || [[ "$(sysctl -n hw.optional.arm64 2>/dev/null || true)" == "1" ]]
}

# The official Homebrew installer refuses Intel Macs since 2026-09 (Homebrew/install#1140).
homebrew_installable() {
  is_apple_silicon
}

macos_at_least() {
  local want_major="$1" want_minor="${2:-0}" version major minor
  version=$(sw_vers -productVersion 2>/dev/null || true)
  major=${version%%.*}
  minor=${version#*.}
  [[ "$minor" == "$version" ]] && minor=0
  minor=${minor%%.*}
  [[ "$major" =~ ^[0-9]+$ ]] || return 1
  [[ "$minor" =~ ^[0-9]+$ ]] || minor=0
  (( major > want_major || (major == want_major && minor >= want_minor) ))
}

sudo_ready=0
ensure_sudo() {
  if [[ $sudo_ready -eq 1 ]]; then
    return 0
  fi
  echo "  입력 대기: Mac 로그인 비밀번호를 요청할 수 있습니다. 입력해도 글자가 보이지 않는 것은 정상입니다."
  if sudo -v; then
    sudo_ready=1
    return 0
  fi
  return 1
}

download_verified() {
  local url="$1" expected_sha="$2" dest="$3" actual_sha
  if ! curl -fsSL --retry 2 "$url" -o "$dest"; then
    return 1
  fi
  actual_sha=$(shasum -a 256 "$dest" 2>/dev/null) || return 1
  [[ "${actual_sha%% *}" == "$expected_sha" ]]
}

# Without Homebrew, Node.js comes from the official nodejs.org installer package.
install_node_from_pkg() {
  local major base shasums pkg_line pkg_sha pkg_name work_dir node_ver result=0

  if macos_at_least 13 5; then
    major=24
  elif macos_at_least 11 0; then
    major=22
  else
    warn "Node.js: 이 macOS 버전은 공식 설치 파일이 지원하지 않습니다. macOS를 11 이상으로 업데이트한 뒤 같은 설치 명령으로 다시 시도하세요."
    return 0
  fi

  base="https://nodejs.org/dist/latest-v${major}.x"
  shasums=$(curl -fsSL --retry 2 "$base/SHASUMS256.txt" 2>/dev/null) || shasums=""
  pkg_line=$(printf '%s\n' "$shasums" | grep -E '^[0-9a-f]{64}  node-v[0-9.]+\.pkg$' | head -n 1) || pkg_line=""
  if [[ -z "$pkg_line" ]]; then
    warn "Node.js: 공식 설치 파일 목록을 받지 못했습니다. https://nodejs.org 에서 LTS 설치 파일을 받아 설치할 수 있습니다."
    return 0
  fi
  pkg_sha=${pkg_line%% *}
  pkg_name=${pkg_line##* }

  echo "  Node.js 공식 설치 파일($pkg_name)을 받아 설치합니다..."
  work_dir=$(mktemp -d "${TMPDIR:-/tmp}/claude-setup-node.XXXXXX")
  if ! download_verified "$base/$pkg_name" "$pkg_sha" "$work_dir/$pkg_name"; then
    result=1
  elif ! ensure_sudo; then
    result=2
  elif ! run_with_status sudo installer -pkg "$work_dir/$pkg_name" -target /; then
    result=1
  fi
  rm -f "$work_dir/$pkg_name"
  rmdir "$work_dir" 2>/dev/null || true

  case ":$PATH:" in
    *:/usr/local/bin:*) ;;
    *) export PATH="$PATH:/usr/local/bin" ;;
  esac
  hash -r

  if [[ $result -eq 0 ]] && node_ver=$(node -v 2>&1); then
    ok "Node.js $node_ver 설치 완료"
  elif [[ $result -eq 2 ]]; then
    warn "Node.js: 관리자 인증에 실패했습니다."
  else
    warn "Node.js: 공식 설치 파일 설치 또는 실행 확인에 실패했습니다. https://nodejs.org 에서 LTS 설치 파일을 받아 설치할 수 있습니다."
  fi
}

# Without Homebrew, Git and Python 3 come from Apple's Command Line Tools.
# Same headless softwareupdate route the Homebrew installer uses.
clt_attempted=0
clt_ready=0
install_command_line_tools() {
  local placeholder="/tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress"
  local label

  if [[ $clt_attempted -eq 1 ]]; then
    [[ $clt_ready -eq 1 ]]
    return
  fi
  clt_attempted=1

  if xcode-select -p &>/dev/null; then
    clt_ready=1
    return 0
  fi
  if ! ensure_sudo; then
    return 1
  fi

  echo "  macOS 기본 개발 도구(Command Line Tools)를 설치합니다. 몇 분 걸릴 수 있습니다..."
  sudo touch "$placeholder" || true
  label=$(softwareupdate -l 2>/dev/null |
    grep -B 1 -E 'Command Line Tools' |
    awk -F'*' '/^ *\*/ {print $2}' |
    sed -e 's/^ *Label: //' -e 's/^ *//' |
    sort -V |
    tail -n 1) || label=""

  if [[ -n "$label" ]] && run_with_status sudo softwareupdate -i "$label"; then
    sudo xcode-select --switch /Library/Developer/CommandLineTools || true
  fi
  sudo rm -f "$placeholder" || true
  hash -r

  if xcode-select -p &>/dev/null; then
    clt_ready=1
    return 0
  fi
  return 1
}

# Pinned official builds per macOS floor; iTerm2 updates itself afterwards.
install_iterm_from_zip() {
  local zip_name zip_sha work_dir

  if macos_at_least 13 0; then
    zip_name="iTerm2-3_7_6.zip"
    zip_sha="bb6102e9f57bbe41979ba7c7b1c25d4112e9a5c2142606eeccbe18dc7ee0706f"
  elif macos_at_least 12 4; then
    zip_name="iTerm2-3_6_11.zip"
    zip_sha="36e78c5049560eaa8e122224f6652eb4b229c61cd5e7332d6d25b5c36f7398e7"
  elif macos_at_least 10 15; then
    zip_name="iTerm2-3_5_14.zip"
    zip_sha="585bd119e4cf3a5e6bfa6f3b6afecf416f02e28f8d81a3a1e949855da058cbdd"
  else
    warn "iTerm2: 이 macOS 버전은 iTerm2를 지원하지 않습니다. 기본 터미널에서 claude를 실행하세요."
    return 0
  fi

  echo "  iTerm2 공식 파일을 받아 설치합니다..."
  mkdir -p "$HOME/Applications"
  work_dir=$(mktemp -d "${TMPDIR:-/tmp}/claude-setup-iterm.XXXXXX")
  if download_verified "https://iterm2.com/downloads/stable/$zip_name" "$zip_sha" "$work_dir/$zip_name" &&
     ditto -x -k "$work_dir/$zip_name" "$HOME/Applications" &&
     [[ -x "$HOME/Applications/iTerm.app/Contents/MacOS/iTerm2" ]]; then
    iterm_app="$HOME/Applications/iTerm.app"
    ok "iTerm2 앱 실행 파일 확인 완료"
  else
    warn "iTerm2: 설치 또는 앱 실행 파일 확인에 실패했습니다. https://iterm2.com/downloads.html 에서 설치할 수 있습니다."
  fi
  rm -f "$work_dir/$zip_name"
  rmdir "$work_dir" 2>/dev/null || true
}

install_if_missing_node() {
  local node_ver

  if command -v node &>/dev/null && node_ver=$(node -v 2>&1); then
    skip "Node.js $node_ver"
    return 0
  fi

  if ! ensure_brew_in_path; then
    install_node_from_pkg
    return 0
  fi

  echo "  Node.js를 설치합니다..."
  if run_with_status env HOMEBREW_NO_ASK=1 brew install node && node_ver=$(node -v 2>&1); then
    ok "Node.js $node_ver 설치 완료"
  else
    warn "Node.js: Homebrew 설치 또는 실행 확인에 실패했습니다."
  fi
}

install_if_missing_python() {
  local py_ver

  if command -v python3 &>/dev/null && ! is_clt_stub python3 && py_ver=$(python3 --version 2>&1); then
    skip "$py_ver"
    return 0
  fi

  if ! ensure_brew_in_path; then
    if install_command_line_tools && py_ver=$(python3 --version 2>&1); then
      ok "$py_ver 설치 완료 (macOS 기본 개발 도구)"
    else
      warn "Python 3: macOS 기본 개발 도구 설치에 실패했습니다. 터미널에 python3 --version 을 입력하면 macOS가 설치 창을 띄웁니다."
    fi
    return 0
  fi

  echo "  Python 3를 설치합니다..."
  if run_with_status env HOMEBREW_NO_ASK=1 brew install python && py_ver=$(python3 --version 2>&1); then
    ok "$py_ver 설치 완료"
  else
    warn "Python 3: Homebrew 설치 또는 실행 확인에 실패했습니다."
  fi
}

install_if_missing_git() {
  local git_ver

  if command -v git &>/dev/null && ! is_clt_stub git && git_ver=$(git --version 2>&1); then
    skip "$git_ver"
    return 0
  fi

  if ! ensure_brew_in_path; then
    if install_command_line_tools && git_ver=$(git --version 2>&1); then
      ok "$git_ver 설치 완료 (macOS 기본 개발 도구)"
    else
      warn "Git: macOS 기본 개발 도구 설치에 실패했습니다. 터미널에 git --version 을 입력하면 macOS가 설치 창을 띄웁니다."
    fi
    return 0
  fi

  echo "  Git을 설치합니다..."
  if run_with_status env HOMEBREW_NO_ASK=1 brew install git && git_ver=$(git --version 2>&1); then
    ok "$git_ver 설치 완료"
  else
    warn "Git: Homebrew 설치 또는 실행 확인에 실패했습니다."
  fi
}

ensure_config_line() {
  local config_file="$1"
  local config_line="$2"

  mkdir -p "$(dirname "$config_file")"
  touch "$config_file"

  if ! grep -Fqx "$config_line" "$config_file"; then
    printf '\n%s\n' "$config_line" >> "$config_file"
  fi
}

persist_brew_path() {
  local brew_bin="$1"
  local shell_name
  local path_line="eval \"\$($brew_bin shellenv)\""

  shell_name=$(basename "${SHELL:-/bin/zsh}")

  case "$shell_name" in
    zsh)
      ensure_config_line "${ZDOTDIR:-$HOME}/.zprofile" "$path_line" || return 1
      ensure_config_line "${ZDOTDIR:-$HOME}/.zshrc" "$path_line" || return 1
      ;;
    bash)
      ensure_config_line "$HOME/.bash_profile" "$path_line" || return 1
      ensure_config_line "$HOME/.bashrc" "$path_line" || return 1
      ;;
    fish)
      ensure_config_line "$HOME/.config/fish/config.fish" "$brew_bin shellenv | source" || return 1
      ;;
    *)
      ensure_config_line "$HOME/.profile" "$path_line" || return 1
      ;;
  esac
}

persist_claude_path() {
  local shell_name
  local path_line='case "$PATH" in "$HOME/.local/bin"|"$HOME/.local/bin":*) ;; *) export PATH="$HOME/.local/bin:$PATH" ;; esac'

  shell_name=$(basename "${SHELL:-/bin/zsh}")

  case "$shell_name" in
    zsh)
      ensure_config_line "${ZDOTDIR:-$HOME}/.zprofile" "$path_line"
      ensure_config_line "${ZDOTDIR:-$HOME}/.zshrc" "$path_line"
      ;;
    bash)
      ensure_config_line "$HOME/.bash_profile" "$path_line"
      ensure_config_line "$HOME/.bashrc" "$path_line"
      ;;
    fish)
      ensure_config_line "$HOME/.config/fish/config.fish" 'fish_add_path "$HOME/.local/bin"'
      ;;
    *)
      ensure_config_line "$HOME/.profile" "$path_line"
      ;;
  esac
}

verify_claude_code() {
  local candidate="$1"
  local version_output

  if ! version_output=$("$candidate" --version 2>&1); then
    return 1
  fi

  case "$version_output" in
    *"(Claude Code)"*)
      claude_ver="$version_output"
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

verify_claude_in_fresh_shell() {
  local expected_path="$1"
  local shell_path="${SHELL:-/bin/zsh}"
  local shell_name
  local version_output
  local clean_path='/usr/bin:/bin:/usr/sbin:/sbin'
  local -a clean_env

  shell_name=$(basename "$shell_path")
  clean_env=(/usr/bin/env -i "HOME=$HOME" "PATH=$clean_path" "SHELL=$shell_path" "EXPECTED_CLAUDE_PATH=$expected_path")
  [[ -n "${USER:-}" ]] && clean_env+=("USER=$USER")
  [[ -n "${LOGNAME:-}" ]] && clean_env+=("LOGNAME=$LOGNAME")
  [[ -n "${LANG:-}" ]] && clean_env+=("LANG=$LANG")
  [[ -n "${LC_ALL:-}" ]] && clean_env+=("LC_ALL=$LC_ALL")
  [[ -n "${ZDOTDIR:-}" ]] && clean_env+=("ZDOTDIR=$ZDOTDIR")
  [[ -n "${XDG_CONFIG_HOME:-}" ]] && clean_env+=("XDG_CONFIG_HOME=$XDG_CONFIG_HOME")

  if [[ "$shell_name" == "fish" ]]; then
    if ! version_output=$("${clean_env[@]}" "$shell_path" -lc 'test (command -s claude) = "$EXPECTED_CLAUDE_PATH"; and claude --version' 2>&1); then
      return 1
    fi
  else
    if ! version_output=$("${clean_env[@]}" "$shell_path" -lc 'test "$(command -v claude)" = "$EXPECTED_CLAUDE_PATH" && claude --version' 2>&1); then
      return 1
    fi
  fi

  case "$version_output" in
    *"(Claude Code)"*) return 0 ;;
    *) return 1 ;;
  esac
}

echo ""
echo -e "${BOLD}🚀 클로드 코드 올인원 설치를 시작합니다${NC}"
echo -e "   macOS $(sw_vers -productVersion) | $(uname -m)"
echo ""

# ── 1. Claude Code ──
progress "Claude Code" "컴퓨터에서 AI와 대화하고 작업을 맡기는 도구입니다."

# Recover an existing valid native install before checking other commands.
claude_native_bin="$HOME/.local/bin/claude"
if [[ -x "$claude_native_bin" ]] && verify_claude_code "$claude_native_bin"; then
  persist_claude_path
  export PATH="$HOME/.local/bin:$PATH"
  hash -r
fi

claude_command=$(command -v claude 2>/dev/null || true)
claude_is_currently_valid=0
if [[ "$claude_command" == /* ]] && verify_claude_code "$claude_command"; then
  claude_is_currently_valid=1
fi

if [[ $claude_is_currently_valid -eq 1 ]] && verify_claude_in_fresh_shell "$claude_command"; then
  skip "Claude Code"
else
  if [[ -n "$claude_command" ]]; then
    if [[ $claude_is_currently_valid -eq 1 ]]; then
      echo -e "  ${YELLOW}!${NC} 현재 셸에서만 Claude Code가 보여 새 터미널에서도 실행되도록 복구합니다."
    else
      echo -e "  ${YELLOW}!${NC} 기존 claude 명령이 Claude Code가 아니거나 실행되지 않아 다시 설치합니다."
    fi
  fi

  echo "  Claude Code를 설치합니다..."
  if ! curl -fsSL https://claude.ai/install.sh | /bin/bash -s stable; then
    fail "Claude Code 설치가 실패했습니다."
  fi

  if ! verify_claude_code "$claude_native_bin"; then
    fail "Claude Code 공식 설치기가 실행 가능한 네이티브 파일을 만들지 못했습니다."
  fi

  persist_claude_path
  export PATH="$HOME/.local/bin:$PATH"
  hash -r
fi

claude_command=$(command -v claude 2>/dev/null || true)
if [[ "$claude_command" != /* ]] || ! verify_claude_code "$claude_command"; then
  fail "Claude Code 명령어의 최종 실행 확인에 실패했습니다."
fi
if ! verify_claude_in_fresh_shell "$claude_command"; then
  fail "Claude Code는 현재 셸에서 실행되지만 새 터미널의 PATH 확인에 실패했습니다."
fi

ok "Claude Code $claude_ver 설치 및 실행 확인"

# ── 2. Homebrew (패키지 매니저) ──
progress "Homebrew (설치 관리자)" "필요한 도구를 하나씩 찾아 설치하지 않도록 도와줍니다."

if ensure_brew_in_path; then
  brew_bin=$(command -v brew)
  brew_ver=$(get_brew_version)
  if persist_brew_path "$brew_bin"; then
    skip "$brew_ver"
  else
    warn "Homebrew: 새 터미널용 PATH 등록에 실패했습니다."
  fi
elif ! homebrew_installable; then
  homebrew_skipped=1
  echo -e "  ${YELLOW}→${NC} 인텔 Mac은 Homebrew 공식 설치기가 더 이상 지원하지 않아 건너뜁니다."
  echo "  다음 단계의 도구는 각 공식 설치 파일로 바로 설치합니다."
else
  echo "  Homebrew를 설치합니다..."
  echo "  필요한 경우 Homebrew가 macOS 기본 개발 도구도 함께 설치합니다."
  homebrew_install_error=""

  echo "  입력 대기: Mac 로그인 비밀번호를 요청할 수 있습니다. 입력해도 글자가 보이지 않는 것은 정상입니다."
  if ! sudo -v; then
    homebrew_install_error="Homebrew: 관리자 인증에 실패했습니다."
  elif ! curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh | NONINTERACTIVE=1 /bin/bash; then
    homebrew_install_error="Homebrew: 공식 설치기 실행에 실패했습니다."
  fi

  if ensure_brew_in_path; then
    brew_bin=$(command -v brew)
    brew_ver=$(get_brew_version)
    if persist_brew_path "$brew_bin"; then
      ok "$brew_ver 설치 및 PATH 등록 완료"
    else
      warn "Homebrew: 설치됐지만 새 터미널용 PATH 등록에 실패했습니다."
    fi
  else
    warn "${homebrew_install_error:-Homebrew: 설치 후 실행 확인에 실패했습니다.}"
  fi
fi

# ── 3. Node.js ──
progress "Node.js" "앱과 사용량 표시 같은 추가 도구를 실행할 때 씁니다."
install_if_missing_node

# ── 4. Python 3 ──
progress "Python 3" "이후 자료 정리와 자동화 작업에 쓰는 도구입니다. 뉴스 대화 자체의 필수 조건은 아닙니다."
install_if_missing_python

# ── 5. Git ──
progress "Git" "이후 작업 파일의 변경 내역을 관리하는 도구입니다."
install_if_missing_git

# ── 6. iTerm2 ──
progress "iTerm2" "앞으로 Claude Code를 실행할 창을 준비합니다. 기존 터미널 설정은 바꾸지 않습니다."
iterm_app=""
for candidate in "$HOME/Applications/iTerm.app" /Applications/iTerm.app; do
  if [[ -x "$candidate/Contents/MacOS/iTerm2" ]]; then
    iterm_app="$candidate"
    break
  fi
done
if [[ -n "$iterm_app" ]]; then
  skip "iTerm2"
elif ensure_brew_in_path; then
  mkdir -p "$HOME/Applications"
  if run_with_status env HOMEBREW_NO_ASK=1 brew install --cask --appdir="$HOME/Applications" iterm2 &&
     [[ -x "$HOME/Applications/iTerm.app/Contents/MacOS/iTerm2" ]]; then
    iterm_app="$HOME/Applications/iTerm.app"
    ok "iTerm2 앱 실행 파일 확인 완료"
  else
    warn "iTerm2: 설치 또는 앱 실행 파일 확인에 실패했습니다. https://iterm2.com/downloads.html 에서 설치할 수 있습니다."
  fi
else
  install_iterm_from_zip
fi
# ── 7. 사용량 모드 ──
progress "사용량 모드" "Claude 사용 한도와 대화 상태를 표시합니다. 터미널 꾸미기와는 별개입니다."
mode_source=""
if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
  mode_source="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/usage-mode"
fi
mode_temp=""
if [[ ! -f "$mode_source/install.mjs" ]]; then
  mode_temp=$(mktemp -d "${TMPDIR:-/tmp}/claude-usage-mode.XXXXXX")
  mode_source="$mode_temp"
  mode_download_ok=1
  for asset in install.mjs usage-line.mjs render.mjs LICENSE; do
    if ! curl -fsSL "https://raw.githubusercontent.com/jsk3342/claude-setup/${CLAUDE_SETUP_REF:-main}/usage-mode/$asset" -o "$mode_source/$asset"; then
      mode_download_ok=0
      break
    fi
  done
else
  mode_download_ok=1
fi
if [[ $mode_download_ok -eq 1 ]] && command -v node &>/dev/null && node "$mode_source/install.mjs"; then
  ok "사용량 모드 설치 및 설정 연결 확인"
else
  warn "사용량 모드: 파일 다운로드 또는 설정 연결에 실패했습니다. 기존 설정을 확인하고 같은 설치 명령으로 다시 시도하세요."
fi
if [[ -n "$mode_temp" ]]; then
  rm -f "$mode_temp/install.mjs" "$mode_temp/usage-line.mjs" "$mode_temp/render.mjs" "$mode_temp/LICENSE"
  rmdir "$mode_temp"
fi
finish_step
echo "  확인 완료 $completed/$total 단계"

# ── 완료 ──
echo ""
if [[ ${#warnings[@]} -eq 0 ]]; then
  echo -e "${GREEN}${BOLD}  ✅ 설치가 모두 완료되었습니다!${NC}"
else
  echo -e "${YELLOW}${BOLD}  ⚠ Claude Code 설치 완료, 추가 환경 일부 미완료${NC}"
fi

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  설치된 항목:"
if command -v brew &>/dev/null && brew_ver=$(get_brew_version); then
  echo -e "  ${GREEN}✓${NC} Homebrew  $brew_ver"
elif [[ $homebrew_skipped -eq 1 ]]; then
  echo -e "  ${YELLOW}→${NC} Homebrew  인텔 Mac이라 생략 (도구는 공식 설치 파일로 설치)"
else
  echo -e "  ${YELLOW}✗${NC} Homebrew  미설치"
fi
if command -v node &>/dev/null && node_ver=$(node -v 2>&1); then
  echo -e "  ${GREEN}✓${NC} Node.js   $node_ver"
else
  echo -e "  ${YELLOW}✗${NC} Node.js   미설치"
fi
if command -v python3 &>/dev/null && ! is_clt_stub python3 && py_ver=$(python3 --version 2>&1); then
  echo -e "  ${GREEN}✓${NC} Python    $py_ver"
else
  echo -e "  ${YELLOW}✗${NC} Python    미설치"
fi
if command -v git &>/dev/null && ! is_clt_stub git && git_ver=$(git --version 2>&1); then
  echo -e "  ${GREEN}✓${NC} Git       $git_ver"
else
  echo -e "  ${YELLOW}✗${NC} Git       미설치"
fi
echo -e "  ${GREEN}✓${NC} Claude Code $claude_ver"
echo ""
echo -e "  ${BOLD}다음 단계:${NC}"
if [[ -n "$iterm_app" ]]; then
  echo "  Finder에서 $iterm_app 을 열어주세요."
else
  echo "  iTerm2 수동 설치 전에도 새 기본 터미널에서 Claude Code를 실행할 수 있습니다."
fi
echo -e "  ${BOLD}새 터미널 창에서${NC} ${YELLOW}claude${NC} 를 입력하세요."
echo -e "  처음 실행하면 Anthropic 계정 연결을 안내합니다."
echo "  로그인 후 Claude 대화 화면에: 오늘 뉴스 정리해서 알려줘"
echo "  설치 명령은 터미널에, 이 요청은 Claude 대화 화면에 입력합니다."
echo "  다음에 사용할 때도 iTerm2를 열고 claude를 입력하면 됩니다. 다시 설치하지 않습니다."
echo ""
echo -e "  ${BOLD}로그인에서 막힐 때:${NC}"
echo -e "  OAuth 400 또는 코드 붙여넣기 문제가 나면 ${YELLOW}claude auth login${NC} 으로 다시 로그인하세요."
echo -e "  브라우저가 안 열리면 로그인 화면에서 ${YELLOW}c${NC} 를 눌러 주소를 복사한 뒤 Chrome에 붙여넣으세요."
print_warning_summary
echo ""

if [[ ${#warnings[@]} -gt 0 ]]; then
  exit 1
fi
