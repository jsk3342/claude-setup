# macOS 기본 개발환경 설치 중 Node.js 실패 대응 기록

- 상태: 코드 수정 및 `main` 반영 완료, 제보자 재실행 검증 대기
- 작업일: 2026-08-21 (KST)
- 최종 릴리스: [`d51a735`](https://github.com/jsk3342/claude-setup/commit/d51a7356ae195ecb1d889be5bda3de0cedc14643)
- 중간 수정: [`29b8c34`](https://github.com/jsk3342/claude-setup/commit/29b8c34525427a44349e290ea8a2cb1a9c3c7d31)

## 목표

일반 사용자가 macOS 터미널에 한 줄을 붙여 넣으면 Claude Code와 기본 개발 도구인 Homebrew, Node.js, Python 3, Git이 실제로 실행 가능한 상태까지 설치되어야 한다.

한 도구의 실패가 다른 도구의 설치 기회를 불필요하게 막으면 안 되며, 일부만 설치된 상태를 전체 성공으로 표시해서도 안 된다.

## 못 빼는 핵심

- Node.js, Python 3, Git은 우연히 포함된 의존성이 아니라 기본 개발환경을 한 번에 제공하기 위한 제품 범위다.
- Claude Code는 네이티브 설치기를 사용하므로 Node.js 설치보다 먼저 독립적으로 설치할 수 있다.
- Claude Code를 먼저 설치해도 전체 성공은 Homebrew, Node.js, Python 3, Git까지 모두 실행 확인된 경우에만 인정한다.
- 전체 Xcode 앱은 설치하지 않는다.
- Homebrew에 필요한 Command Line Tools는 별도 사용자 단계로 중복 구현하지 않고 Homebrew 공식 설치기에 맡긴다.
- 정확한 원인이 확인되지 않은 Homebrew 오류를 수정 완료라고 단정하지 않는다.

## 최초 제보

외부 사용자가 macOS 설치 스크립트를 실행하던 중 Node.js 단계에서 다음 오류를 보고했다.

```text
node: An exception occurred within a child process:
    Errno::ENOENT: No such file or directory @ rb_sysopen -
```

## 확인된 사실

- 오류는 Claude Code가 아니라 `brew install node` 실행 중 Homebrew의 자식 프로세스에서 발생했다.
- 당시 스크립트는 `set -e` 상태여서 Node.js 설치가 실패하면 Python 3, Git, Claude Code 단계까지 모두 중단됐다.
- Anthropic 네이티브 설치기는 Node.js가 아니라 `curl` 또는 `wget`으로 Claude Code를 설치한다.
- `xcode-select --install`이 설치하는 것은 전체 Xcode 앱이 아니라 macOS 명령줄 개발 도구다.
- Homebrew 공식 설치기는 해당 개발 도구가 없으면 자체 설치 흐름으로 처리한다.

## 미확인

- 제보 메시지의 `rb_sysopen -` 뒤에 있어야 할 누락 파일 경로가 전달되지 않았다.
- 제보자의 전체 Homebrew 출력, macOS 버전, CPU, Homebrew 상태를 받지 못했다.
- 따라서 최초 `ENOENT`의 단일 원인은 캐시, 지원되지 않는 macOS, 손상된 Homebrew 또는 다른 환경 문제 중 어느 것인지 확정하지 않았다.

## 레드팀에서 교정된 판단

### 중간 판단

`29b8c34`에서는 Claude Code를 먼저 설치하고 Homebrew, Node.js, Python 3, Git 실패를 경고로 낮췄다. 이 변경은 Node.js 실패가 Claude Code 설치까지 막는 피해는 줄였다.

### 발견된 문제

- Node.js, Python 3, Git을 선택 항목으로 낮춰 원래의 기본 개발환경 제공 목적을 바꿨다.
- 일부 개발 도구가 빠져도 종료 코드 `0`과 완료 안내를 낼 수 있었다.
- Homebrew를 `NONINTERACTIVE=1`로 실행하면서 사전 관리자 인증을 제거해 새 Mac에서 Homebrew 설치가 실패할 수 있었다.
- 별도 Command Line Tools 설치 단계는 Homebrew 공식 설치기와 책임이 중복됐고 60초 타임아웃도 실제 설치 시간과 맞지 않았다.
- 기존 macOS 회귀 테스트는 Claude 설치 실패에서 끝나 새 Homebrew와 개발 도구 분기를 검사하지 않았다.

### 최종 결정

- Claude Code를 먼저 설치하는 순서는 유지한다.
- Homebrew, Node.js, Python 3, Git은 전체 설치 성공에 필요한 기본 개발 도구로 유지한다.
- 독립 Command Line Tools 단계는 제거한다.
- Homebrew가 없을 때만 `sudo -v`로 관리자 인증을 받고 공식 Homebrew 설치기를 실행한다.
- 개발 도구 하나라도 설치 또는 버전 확인에 실패하면 Claude Code가 실행되더라도 전체 설치는 종료 코드 `1`로 끝낸다.

## 최종 설치 흐름

1. Claude Code 공식 `stable` 설치 및 현재 셸 버전 확인
2. 새 로그인 셸에서 Claude Code PATH와 버전 확인
3. Homebrew 확인 또는 공식 설치
4. Node.js, Python 3, Git 설치 및 각각의 버전 확인
5. 모든 결과를 요약하고 전체 성공 또는 부분 실패로 종료

## 파일별 변경

| 파일 | 변경 |
|---|---|
| [`install.sh`](../install.sh) | 독립 CLT 단계 제거, Homebrew 관리자 인증 범위 제한, PATH 영속화, 개발 도구 실제 버전 확인, 부분 실패 시 종료 코드 `1` |
| [`README.md`](../README.md) | 실제 설치 순서와 Homebrew의 macOS 개발 도구 처리, 전체 완료 기준 설명 |
| [`tests/install-macos-regression.sh`](../tests/install-macos-regression.sh) | Claude PATH 회귀 유지, 정상 기본 도구 구성 성공, Node.js 실패의 전체 성공 오인 방지 검사 |

## 성공 기준

- [x] Claude Code 설치가 Node.js 설치 실패에 가로막히지 않는다.
- [x] 새 로그인 셸에서 실제 Claude Code가 실행된다.
- [x] 기존 Homebrew가 PATH 밖에 있어도 표준 설치 경로에서 복구한다.
- [x] Homebrew PATH 설정을 셸 설정 파일에 중복 없이 기록한다.
- [x] Node.js, Python 3, Git은 명령 존재가 아니라 버전 명령 성공으로 판정한다.
- [x] 개발 도구 일부가 실패하면 전체 완료 배너를 출력하지 않고 종료 코드 `1`을 반환한다.
- [x] `main`의 원격 커밋과 로컬 릴리스 커밋이 일치한다.
- [ ] 최초 제보자의 Mac에서 최신 설치 스크립트 재실행이 성공한다.

## 실패 기준 / 차단선

- 개발 도구가 빠졌는데 전체 설치 완료로 안내한다.
- Homebrew가 이미 있는데 PATH 문제만으로 공식 설치기를 다시 실행한다.
- Homebrew 설치가 필요한 경우 관리자 인증 없이 비대화형 설치를 시도한다.
- Command Line Tools 설치를 별도 팝업과 임의 타임아웃으로 중복 관리한다.
- 최초 `ENOENT` 원인을 확인하지 않고 특정 macOS 설정 문제로 단정한다.
- 실제 제보 환경 재검증 전 사고를 완전 해결로 닫는다.

## 검증 증거

- `/bin/bash -n install.sh tests/install-macos-regression.sh`: 통과
- `/bin/bash tests/install-macos-regression.sh`: `macOS installer regressions: OK`
- `shellcheck`: 로컬에 실행 파일이 없어 미실행
- `git diff --check`: 통과
- 릴리스 커밋: `d51a7356ae195ecb1d889be5bda3de0cedc14643`
- 원격 `origin/main`: 로컬 릴리스 커밋과 일치

## 검증하지 않은 것

현재 작업 머신에는 Homebrew와 Command Line Tools가 이미 설치되어 있다. 따라서 두 항목이 모두 없는 깨끗한 Mac에서 Homebrew 공식 설치기가 Command Line Tools까지 설치하는 실제 전체 흐름은 실행하지 않았다.

GitHub의 일반 macOS 러너도 기본 개발 도구가 사전 설치되어 있어 이 조건을 그대로 재현하지 못한다. 최초 제보자의 재실행 결과를 현장 스모크 테스트로 사용한다.

정적 검사는 macOS 기본 Bash의 `bash -n`과 회귀 테스트로 수행했다. `shellcheck`는 현재 작업 머신에 설치되어 있지 않아 실행하지 않았다.

## 사용자 안내 문구

> 설치 중 오류가 나던 부분을 수정했습니다. 터미널을 완전히 닫았다가 다시 열고 아래 명령을 그대로 복사해서 실행해 주세요. 중간에 Mac 비밀번호를 물어보면 입력해 주세요. 입력할 때 화면에 글자가 표시되지 않는 것은 정상입니다. 설치가 끝나면 터미널에 `claude`를 입력해 보세요. 다시 오류가 나오면 오류 부분만 자르지 말고 터미널 화면 전체를 캡처해서 보내주세요.

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/jsk3342/claude-setup/main/install.sh)"
```

## 재발 시 필요한 증거

일반 사용자에게는 우선 전체 터미널 화면을 요청한다. 추가 진단이 필요할 때 운영자가 다음 정보를 순서대로 받는다.

```bash
sw_vers -productVersion
uname -m
brew config
brew install node 2>&1 | tee ~/Desktop/brew-node-install.log
```

로그에 개인정보나 로컬 경로가 포함될 수 있으므로 공개 댓글에 올리기 전에 확인하도록 안내한다.

## 롤백 / 전진 수정

- 데이터 변경이나 외부 서비스 마이그레이션은 없다.
- 긴급 롤백이 필요하면 `main`을 강제 푸시하지 않고 `d51a735`를 취소하는 새 revert 커밋을 만든다.
- 최초 오류가 재발하면 현재 구조를 되돌리기보다 전체 로그로 Homebrew 실패 원인을 분류해 전진 수정한다.

## 다음 액션

1. 제보자에게 최신 설치 명령 재실행을 요청한다.
2. 성공하면 최초 제보를 해결 완료로 닫는다.
3. 실패하면 전체 터미널 출력에서 실제 누락 경로와 Homebrew 실패 단계를 확인한다.
4. 새 증거가 없으면 추가 추정이나 자동 복구 코드를 넣지 않는다.
