# 기본 제공 사용량 모드

Kai가 사용 중인 usage-band의 상태줄 렌더러를 이식한 배포 구성이다.
원본 MIT: https://github.com/JetsonChan/CC-Usage-Band
`render.mjs` 안에 ClaudeBar·cache-clock에서 가져온 표시 규칙의 출처가 있다.

5시간·주간 한도, 컨텍스트, 제공되는 캐시 값을 표시한다. 계정이 제공하지 않은
값은 0으로 만들지 않는다. 터미널 외형·프로필·권한 설정을 바꾸지 않는다.
별도 API 호출이나 사용량 기록 파일을 만들지 않는다.

`install.mjs`는 기존 settings.json을 백업하고 상태줄만 연결한다.
기존 상태줄 명령은 같은 입력으로 먼저 실행하고 그 아래에 사용량을 표시한다.
재실행해도 자기 자신을 감싸지 않는다. 잘못된 JSON과 미지원 상태줄은 덮어쓰지 않는다.

이 구성은 터미널의 상태줄 배포본이다. 원본 플러그인의 다른 UI·개인 목표·로그 기록을
함께 설치했다는 뜻은 아니다. 권한 프리셋과 스킬 설치는 이번 변경에 포함하지 않는다.

복구: settings.json의 statusLine을 `previous-statusline.json`의 statusLine 값으로
복원한다. 원래 값이 null이면 statusLine 항목을 삭제한다. 전체 설정 백업을 복원할 때는
설치 이후의 다른 변경을 잃지 않는지 확인한다.
