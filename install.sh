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
total=5
warnings=()

progress() {
  step=$((step + 1))
  echo ""
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${BOLD}[$step/$total] $1${NC}"
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
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
  echo -e "${YELLOW}기본 개발 환경에서 완료되지 않은 항목:${NC}"
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

install_if_missing_node() {
  local node_ver

  if command -v node &>/dev/null && node_ver=$(node -v 2>&1); then
    skip "Node.js $node_ver"
    return 0
  fi

  if ! ensure_brew_in_path; then
    warn "Node.js: Homebrew가 없어 수동 설치가 필요합니다."
    return 0
  fi

  echo "  Node.js를 설치합니다..."
  if brew install node && node_ver=$(node -v 2>&1); then
    ok "Node.js $node_ver 설치 완료"
  else
    warn "Node.js: Homebrew 설치 또는 실행 확인에 실패했습니다."
  fi
}

install_if_missing_python() {
  local py_ver

  if command -v python3 &>/dev/null && py_ver=$(python3 --version 2>&1); then
    skip "$py_ver"
    return 0
  fi

  if ! ensure_brew_in_path; then
    warn "Python 3: Homebrew가 없어 수동 설치가 필요합니다."
    return 0
  fi

  echo "  Python 3를 설치합니다..."
  if brew install python && py_ver=$(python3 --version 2>&1); then
    ok "$py_ver 설치 완료"
  else
    warn "Python 3: Homebrew 설치 또는 실행 확인에 실패했습니다."
  fi
}

install_if_missing_git() {
  local git_ver

  if command -v git &>/dev/null && git_ver=$(git --version 2>&1); then
    skip "$git_ver"
    return 0
  fi

  if ! ensure_brew_in_path; then
    warn "Git: Homebrew가 없어 수동 설치가 필요합니다."
    return 0
  fi

  echo "  Git을 설치합니다..."
  if brew install git && git_ver=$(git --version 2>&1); then
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
progress "Claude Code"

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
progress "Homebrew (패키지 매니저)"

if ensure_brew_in_path; then
  brew_bin=$(command -v brew)
  brew_ver=$(get_brew_version)
  if persist_brew_path "$brew_bin"; then
    skip "$brew_ver"
  else
    warn "Homebrew: 새 터미널용 PATH 등록에 실패했습니다."
  fi
else
  echo "  Homebrew를 설치합니다..."
  echo "  필요한 경우 Homebrew가 macOS 기본 개발 도구도 함께 설치합니다."
  homebrew_install_error=""

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
progress "Node.js"
install_if_missing_node

# ── 4. Python 3 ──
progress "Python 3"
install_if_missing_python

# ── 5. Git ──
progress "Git"
install_if_missing_git

# ── 완료 ──
echo ""
if [[ ${#warnings[@]} -eq 0 ]]; then
  echo -e "${GREEN}${BOLD}  ✅ 설치가 모두 완료되었습니다!${NC}"
else
  echo -e "${YELLOW}${BOLD}  ⚠ Claude Code 설치 완료, 기본 개발 환경 일부 미완료${NC}"
fi

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  설치된 항목:"
if command -v brew &>/dev/null && brew_ver=$(get_brew_version); then
  echo -e "  ${GREEN}✓${NC} Homebrew  $brew_ver"
else
  echo -e "  ${YELLOW}✗${NC} Homebrew  미설치"
fi
if command -v node &>/dev/null && node_ver=$(node -v 2>&1); then
  echo -e "  ${GREEN}✓${NC} Node.js   $node_ver"
else
  echo -e "  ${YELLOW}✗${NC} Node.js   미설치"
fi
if command -v python3 &>/dev/null && py_ver=$(python3 --version 2>&1); then
  echo -e "  ${GREEN}✓${NC} Python    $py_ver"
else
  echo -e "  ${YELLOW}✗${NC} Python    미설치"
fi
if command -v git &>/dev/null && git_ver=$(git --version 2>&1); then
  echo -e "  ${GREEN}✓${NC} Git       $git_ver"
else
  echo -e "  ${YELLOW}✗${NC} Git       미설치"
fi
echo -e "  ${GREEN}✓${NC} Claude Code $claude_ver"
echo ""
echo -e "  ${BOLD}다음 단계:${NC}"
echo -e "  ${BOLD}현재 터미널 창을 닫고 새로 연 뒤${NC} ${YELLOW}claude${NC} 를 입력하세요."
echo -e "  처음 실행하면 Anthropic 계정 연결을 안내합니다."
echo ""
echo -e "  ${BOLD}로그인에서 막힐 때:${NC}"
echo -e "  OAuth 400 또는 코드 붙여넣기 문제가 나면 ${YELLOW}claude auth login${NC} 으로 다시 로그인하세요."
echo -e "  브라우저가 안 열리면 로그인 화면에서 ${YELLOW}c${NC} 를 눌러 주소를 복사한 뒤 Chrome에 붙여넣으세요."
print_warning_summary
echo ""

if [[ ${#warnings[@]} -gt 0 ]]; then
  exit 1
fi
