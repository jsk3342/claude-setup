#!/bin/bash
# ============================================================
# 클로드 코드 올인원 설치 스크립트 (macOS)
# 사용법: /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/jsk3342/claude-setup/main/install.sh)"
# ============================================================

set -e

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

if command -v claude &>/dev/null; then
  skip "Claude Code"
else
  echo "  Claude Code를 설치합니다..."
  brew install --cask claude-code
  ok "Claude Code 설치 완료"
fi

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
echo -e "  ${GREEN}✓${NC} Claude Code"
echo ""
echo -e "  ${BOLD}다음 단계:${NC}"
echo -e "  터미널에 ${YELLOW}claude${NC} 를 입력하면 클로드 코드가 실행됩니다."
echo -e "  처음 실행하면 Anthropic 계정 연결을 안내합니다."
echo ""
