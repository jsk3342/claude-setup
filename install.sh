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

# ── sudo 미리 획득 (이후 비밀번호 재입력 없음) ──
echo -e "  설치에 관리자 권한이 필요합니다."
sudo -v
# sudo 타임아웃 방지 (백그라운드에서 갱신)
while true; do sudo -n true; sleep 50; kill -0 "$$" || exit; done 2>/dev/null &

# ── 1. Xcode Command Line Tools ──
progress "Xcode Command Line Tools"

if xcode-select -p &>/dev/null; then
  skip "Xcode CLT"
else
  echo "  Xcode Command Line Tools를 설치합니다..."
  echo "  (팝업이 뜨면 '설치'를 눌러주세요)"
  xcode-select --install 2>/dev/null || true

  # 설치 완료 대기
  echo "  설치가 완료될 때까지 기다립니다..."
  until xcode-select -p &>/dev/null; do
    sleep 5
  done
  ok "Xcode CLT 설치 완료"
fi

# ── 2. Homebrew ──
progress "Homebrew (패키지 매니저)"

if command -v brew &>/dev/null; then
  skip "Homebrew"
else
  echo "  Homebrew를 설치합니다..."
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

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

# brew가 PATH에 있는지 재확인
if ! command -v brew &>/dev/null; then
  # 직접 경로로 시도
  if [[ -f /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -f /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  else
    fail "Homebrew 설치에 실패했습니다. 터미널을 재시작한 뒤 다시 시도해주세요."
  fi
fi

# ── 3. Node.js ──
progress "Node.js"

if command -v node &>/dev/null; then
  node_ver=$(node -v)
  skip "Node.js $node_ver"
else
  echo "  Node.js를 설치합니다..."
  brew install node
  ok "Node.js $(node -v) 설치 완료"
fi

# ── 4. Python 3 ──
progress "Python 3"

if command -v python3 &>/dev/null; then
  py_ver=$(python3 --version 2>&1)
  skip "$py_ver"
else
  echo "  Python 3를 설치합니다..."
  brew install python
  ok "$(python3 --version) 설치 완료"
fi

# ── 5. Git ──
progress "Git"

if command -v git &>/dev/null; then
  git_ver=$(git --version)
  skip "$git_ver"
else
  echo "  Git을 설치합니다..."
  brew install git
  ok "$(git --version) 설치 완료"
fi

# ── 6. Claude Code ──
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
  curl -fsSL https://claude.ai/install.sh | /bin/bash -s stable

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

# ── 완료 ──
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}${BOLD}  ✅ 설치가 모두 완료되었습니다!${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  설치된 항목:"
echo -e "  ${GREEN}✓${NC} Homebrew  $(brew --version 2>/dev/null | head -1)"
echo -e "  ${GREEN}✓${NC} Node.js   $(node -v 2>/dev/null)"
echo -e "  ${GREEN}✓${NC} Python    $(python3 --version 2>&1)"
echo -e "  ${GREEN}✓${NC} Git       $(git --version 2>/dev/null)"
echo -e "  ${GREEN}✓${NC} Claude Code $claude_ver"
echo ""
echo -e "  ${BOLD}다음 단계:${NC}"
echo -e "  ${BOLD}현재 터미널 창을 닫고 새로 연 뒤${NC} ${YELLOW}claude${NC} 를 입력하세요."
echo -e "  처음 실행하면 Anthropic 계정 연결을 안내합니다."
echo ""
echo -e "  ${BOLD}로그인에서 막힐 때:${NC}"
echo -e "  OAuth 400 또는 코드 붙여넣기 문제가 나면 ${YELLOW}claude auth login${NC} 으로 다시 로그인하세요."
echo -e "  브라우저가 안 열리면 로그인 화면에서 ${YELLOW}c${NC} 를 눌러 주소를 복사한 뒤 Chrome에 붙여넣으세요."
echo ""
