# Claude Code 올인원 설치

터미널에 한 줄 복사하면 클로드 코드 환경이 세팅됩니다.

## macOS

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/jsk3342/claude-setup/main/install.sh)"
```

설치 항목: Xcode CLT → Homebrew → Node.js → Python 3 → Git → Claude Code

## Windows

PowerShell을 열고:

```powershell
irm https://raw.githubusercontent.com/jsk3342/claude-setup/main/install.ps1 | iex
```

설치 항목: Scoop → Node.js → Python 3 → Git → Claude Code

## 뭐가 설치되나요?

| 도구 | 용도 |
|------|------|
| Homebrew / Scoop | 패키지 매니저 (앱스토어 같은 것) |
| Node.js | JavaScript 런타임 (프로젝트 개발용) |
| Python 3 | 스크립트, 자동화에 사용 |
| Git | 버전 관리 |
| Claude Code | AI와 대화하며 일하는 터미널 도구 |

- 이미 설치된 항목은 자동으로 스킵합니다
- Apple Silicon(M1/M2/M3/M4) 자동 대응
- 설치 중 진행 상황이 표시됩니다

## Windows 초기화 (클린 테스트용)

기존 설치를 전부 제거하고 클린 상태로 만듭니다:

```powershell
irm https://raw.githubusercontent.com/jsk3342/claude-setup/main/uninstall-win.ps1 | iex
```

PowerShell 재시작 후 위의 설치 명령어를 다시 실행하면 됩니다.
