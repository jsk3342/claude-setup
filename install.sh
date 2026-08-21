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
total=6
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
  echo -e "${YELLOW}아래 항목은 Claude Code와 별개로 설치되지 않았습니다.${NC}"
  for item in "${warnings[@]}"; do
    echo "  - $item"
  done
}

ensure_brew_in_path() {
  if command -v brew &>/dev/null; then
    return 0
  fi

  if [[ -f /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
    return 0
  fi

  if [[ -f /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
    return 0
  fi

  return 1
}

install_if_missing_node() {
  if command -v node &>/dev/null; then
    node_ver=$(node -v)
    skip "Node.js $node_ver"
    return 0
  fi

  if ! ensure_brew_in_path; then
    warn "Node.js: Homebrew가 없어 수동 설치가 필요합니다."
    return 0
  fi

  echo "  Node.js를 설치합니다..."
  if brew install node; then
    ok "Node.js $(node -v) 설치 완료"
  else
    warn "Node.js: Homebrew 설치 중 실패했습니다. (개발 도구 필요 시 수동으로 설치하세요)"
  fi
}

install_if_missing_python() {
  if command -v python3 &>/dev/null; then
    py_ver=$(python3 --version 2>&1)
    skip "$py_ver"
    return 0
  fi

  if ! ensure_brew_in_path; then
    warn "Python 3: Homebrew가 없어 수동 설치가 필요합니다."
    return 0
  fi

  echo "  Python 3를 설치합니다..."
  if brew install python; then
    ok "$(python3 --version) 설치 완료"
  else
    warn "Python 3: Homebrew 설치 중 실패했습니다. (개발 도구 필요 시 수동으로 설치하세요)"
  fi
}

install_if_missing_git() {
  if command -v git &>/dev/null; then
    git_ver=$(git --version)
    skip "$git_ver"
    return 0
  fi

  if ! ensure_brew_in_path; then
    warn "Git: Homebrew가 없어 수동 설치가 필요합니다."
    return 0
  fi

  echo "  Git을 설치합니다..."
  if brew install git; then
    ok "$(git --version) 설치 완료"
  else
    warn "Git: Homebrew 설치 중 실패했습니다. (개발 도구 필요 시 수동으로 설치하세요)"
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

# ── 2. Xcode Command Line Tools ──
progress "Xcode Command Line Tools"

if xcode-select -p &>/dev/null; then
  skip "Xcode CLT"
else
  echo "  Xcode Command Line Tools를 설치합니다..."
  echo "  (팝업이 뜨면 '설치'를 눌러주세요)"
  xcode-select --install 2>/dev/null || true
  wait_count=0

  # 설치 완료 대기
  echo "  설치가 완료될 때까지 기다립니다..."
  until xcode-select -p &>/dev/null; do
    sleep 5
    wait_count=$((wait_count + 1))
    if [[ "$wait_count" -ge 12 ]]; then
      warn "Xcode CLT: 사용자 동작 대기 타임아웃. 나중에 수동 설치해 주세요."
      break
    fi
  done

  if xcode-select -p &>/dev/null; then
    ok "Xcode CLT 설치 완료"
  fi
fi

# ── 3. Homebrew (패키지 매니저) ──
progress "Homebrew (패키지 매니저)"

if command -v brew &>/dev/null; then
  skip "Homebrew"
else
  echo "  Homebrew를 설치합니다..."
  if ! NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"; then
    warn "Homebrew: 설치 실패 (개발 도구 단계는 선택 설치로 넘어갑니다)"
  else
    # Apple Silicon PATH 등록
    if [[ "$(uname -m)" == "arm64" ]]; then
      echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> "$HOME/.zprofile"
      eval "$(/opt/homebrew/bin/brew shellenv)"
      ok "Homebrew 설치 + PATH 등록 (Apple Silicon)"
    else
      echo 'eval "$(/usr/local/bin/brew shellenv)"' >> "$HOME/.zprofile"
      eval "$(/usr/local/bin/brew shellenv)"
      ok "Homebrew 설치 + PATH 등록 (Intel)"
    fi
  fi
fi

if ! ensure_brew_in_path; then
  warn "Homebrew 경로 등록이 안 되어 있어 Node/Python/Git은 설치되지 않았습니다."
fi

# ── 4. Node.js ──
progress "Node.js"
install_if_missing_node

# ── 5. Python 3 ──
progress "Python 3"
install_if_missing_python

# ── 6. Git ──
progress "Git"
install_if_missing_git

# ── 완료 ──
echo ""
if [[ ${#warnings[@]} -eq 0 ]]; then
  echo -e "${GREEN}${BOLD}  ✅ 설치가 모두 완료되었습니다!${NC}"
else
  echo -e "${YELLOW}${BOLD}  ✅ 설치(필수) 완료, 선택 항목 일부 미완료${NC}"
fi

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  설치된 항목:"
if command -v brew &>/dev/null; then
  echo -e "  ${GREEN}✓${NC} Homebrew  $(brew --version 2>/dev/null | head -1)"
else
  echo -e "  ${YELLOW}✗${NC} Homebrew  미설치"
fi
if command -v node &>/dev/null; then
  echo -e "  ${GREEN}✓${NC} Node.js   $(node -v)"
else
  echo -e "  ${YELLOW}✗${NC} Node.js   미설치"
fi
if command -v python3 &>/dev/null; then
  echo -e "  ${GREEN}✓${NC} Python    $(python3 --version 2>&1)"
else
  echo -e "  ${YELLOW}✗${NC} Python    미설치"
fi
if command -v git &>/dev/null; then
  echo -e "  ${GREEN}✓${NC} Git       $(git --version)"
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
