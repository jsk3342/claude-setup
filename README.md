# Claude Code 올인원 설치

터미널에 한 줄 복사하면 클로드 코드 환경이 세팅됩니다.

## macOS

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/jsk3342/claude-setup/main/install.sh)"
```

설치 항목: Claude Code → Homebrew → Node.js → Python 3 → Git → iTerm2 → 사용량 모드

## Windows

PowerShell을 열고:

```powershell
irm https://raw.githubusercontent.com/jsk3342/claude-setup/main/install.ps1 | iex
```

설치 항목: Scoop → Node.js → Python 3 → Git → Claude Code → Windows Terminal → 사용량 모드

## 뭐가 설치되나요?

| 도구 | 용도 |
|------|------|
| Homebrew / Scoop | 패키지 매니저 (앱스토어 같은 것) |
| Node.js | JavaScript 런타임 (프로젝트 개발용) |
| Python 3 | 스크립트, 자동화에 사용 |
| Git | 버전 관리 |
| Claude Code | AI와 대화하며 일하는 터미널 도구 |
| iTerm2 / Windows Terminal | Claude Code를 실행할 창 (기존 꾸미기 유지) |
| 사용량 모드 | 계정 사용 한도·컨텍스트·제공되는 캐시 값 표시 |

- 이미 설치된 항목은 자동으로 스킵합니다
- Apple Silicon(M1/M2/M3/M4) 자동 대응
- 설치 중 현재 단계·완료한 단계 수·설치 이유 한 줄이 표시됩니다
- 전체 바는 단계 완료 수이며 남은 시간이나 다운로드 %가 아닙니다
- Mac의 긴 비대화형 도구 설치는 15초마다 실행 중·경과 시간을 표시합니다
- 사용량 모드는 기존 상태줄 출력을 유지하며 추가됩니다. 설정 JSON이 잘못됐으면 덮어쓰지 않습니다
- 기존 터미널 배색·폰트·단축키·프로필·Claude 권한은 바꾸지 않습니다
- Windows Terminal이 없고 winget도 없으면 기존 Scoop으로 공식 포터블 배포본을 설치합니다. 기존 설정 파일을 이전하거나 덮어쓰지 않습니다
- Claude Code 신규 설치는 Anthropic 공식 `stable` 설치기를 사용합니다
- 실제 Claude Code 버전 확인과 새 터미널의 PATH 확인이 모두 통과해야 완료로 판정합니다
- Homebrew가 없는 macOS에서는 관리자 인증 후 공식 설치기를 사용합니다
- Homebrew에 필요한 macOS 기본 개발 도구는 Homebrew 공식 설치기가 함께 처리합니다
- Homebrew, Node.js, Python 3, Git 중 하나라도 실행 확인에 실패하면 전체 완료로 판정하지 않습니다
- 개발 환경 일부가 실패해도 먼저 설치된 Claude Code는 사용할 수 있습니다

## 설치 후 첫 실행

1. Mac은 iTerm2, Windows는 Windows Terminal을 새로 엽니다.
2. `claude`를 입력하고 안내에 따라 계정을 연결합니다.
3. **Claude 대화 화면**에 `오늘 뉴스 정리해서 알려줘`를 입력합니다.
4. 응답 뒤 사용량 표시를 확인합니다. 계정·첫 응답에 따라 한도가 아직 없으면 `확인 전`으로 표시됩니다.
5. 다음에도 같은 앱에서 `claude`를 실행하면 됩니다. 매번 설치하지 않습니다.

설치 명령은 터미널에, 뉴스 요청은 실행된 Claude에 입력합니다.
Python·Git 등은 후속 작업을 위한 공통 도구이며 뉴스 대화 자체의 필수 조건은 아닙니다.

## 꾸미기는 별도 선택

기본 설치는 터미널 앱과 사용량 모드를 준비합니다. 개인 꾸미기는 적용하지 않습니다.
원하는 사람만 별도 [win-iterm2](https://github.com/jsk3342/win-iterm2)의 안내를 따르세요.
이 설치기는 꾸미기 스크립트를 호출하거나 그 설정을 복제하지 않습니다.

사용량 표시의 설치·기존 상태줄 보존·복구는 [usage-mode/README.md](usage-mode/README.md)를 참고하세요.

## 설치 후 `claude` 명령어가 안 보일 때

이전 버전은 PATH가 반영되지 않아도 설치 완료를 표시하는 문제가 있었습니다. 위의 설치 명령어를 다시 한 번 실행한 뒤, **현재 터미널을 완전히 닫고 새 터미널을 열어** 확인하세요.

```bash
claude --version
```

정상이면 버전 번호가 출력됩니다. 최신 스크립트는 이 확인이 실패하면 완료로 표시하지 않습니다.

## Claude 로그인에서 막힐 때

설치는 끝났는데 로그인 중 아래처럼 나오면 설치 실패가 아니라 Claude Code 인증 단계 문제입니다.

```text
OAuth error: Request failed with status code 400
Browser didn't open? Use the url below to sign in (c to copy)
```

먼저 터미널을 새로 열고 아래 명령어로 다시 로그인해보세요.

```bash
claude auth login
```

브라우저가 자동으로 안 열리면 터미널에서 `c`를 눌러 로그인 주소를 복사한 뒤 Chrome에 붙여넣습니다. 인증 코드가 나오면 같은 터미널에 바로 붙여넣고 Enter를 누르세요.

- 코드는 한 번만 쓸 수 있고 금방 만료됩니다.
- 예전에 열어둔 브라우저 화면의 코드를 다시 쓰면 400이 날 수 있습니다.
- 직접 타이핑하면 오타나 만료 때문에 400이 자주 납니다.
- Windows에서 붙여넣기가 안 되면 `Ctrl+V` 대신 오른쪽 클릭 또는 `Shift+Insert`를 시도해보세요.

그래도 안 되면 Claude Code를 로그아웃한 뒤 다시 시도합니다.

```bash
claude
/logout
```

Claude Code를 종료하고 터미널을 새로 연 뒤 다시 실행하세요.

## Windows 초기화 (클린 테스트용)

현재 Windows 사용자의 기존 개발 도구와 Claude Code 설치를 제거해 재설치 테스트 상태로 만듭니다. WinGet 패키지를 제거할 때 Windows가 관리자 승인을 요청할 수 있습니다:

> **주의:** Claude Code만 제거하는 명령이 아닙니다. Scoop과 Scoop 패키지, WinGet으로 설치된 Node.js·Python·Git도 제거하므로 일회용 테스트 환경에서만 실행하세요.

```powershell
irm https://raw.githubusercontent.com/jsk3342/claude-setup/main/uninstall-win.ps1 | iex
```

PowerShell 재시작 후 위의 설치 명령어를 다시 실행하면 됩니다.

`%USERPROFILE%\.local\bin`에 Claude 외의 파일이 있으면 다른 도구를 보호하기 위해 해당 PATH는 유지합니다. PATH 등록까지 완전히 처음인 상태를 시험하려면 새 Windows 사용자나 일회용 VM을 사용하세요.
