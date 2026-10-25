# 앱·도구·웹 단축키 목록

버전 1.0 기준. 데이터는 앱 번들에 포함되며 인터넷 없이 읽습니다. 기본 카탈로그 126개와 추가 팩 238개, 합계 364개입니다. 실제 메뉴를 읽은 항목과 사용자 수정이 추가되면 표시 개수는 달라집니다.

| 목록 | 합계 | 범위 ID | 출처 |
| --- | ---: | --- | --- |
| macOS | 68 | `macOS` | [Apple](https://support.apple.com/en-us/102650) |
| Google 검색 | 11 | `web.google.search` | [Google 검색 접근성](https://support.google.com/websearch/answer/181196?hl=en), [Safari 키보드 조작](https://support.apple.com/en-gb/guide/safari/cpsh003/27.0/mac/27) |
| tmux | 36 | `org.tmux.tmux` | [tmux 매뉴얼](https://man.openbsd.org/tmux), 설치된 tmux 3.7b 매뉴얼 |
| cmux | 42 | `com.cmuxterm.app` | [cmux 공식 단축키](https://cmux.com/docs/keyboard-shortcuts) |
| Finder | 44 | `com.apple.finder` | [Apple](https://support.apple.com/en-us/102650) |
| Safari | 31 | `com.apple.Safari` | [Apple Safari](https://support.apple.com/en-gb/guide/safari/cpsh003/27.0/mac/27) |
| Terminal | 16 | `com.apple.Terminal` | [Apple Terminal](https://support.apple.com/guide/terminal/trmlshtcts/mac) |
| Excel | 40 | `com.microsoft.Excel` | [Microsoft Excel macOS](https://support.microsoft.com/en-us/accessibility/excel/keyboard-shortcuts-in-excel) |
| Word | 36 | `com.microsoft.Word` | [Microsoft Word macOS](https://support.microsoft.com/en-us/accessibility/word/keyboard-shortcuts-in-word) |
| PowerPoint | 40 | `com.microsoft.Powerpoint` | [Microsoft PowerPoint macOS](https://support.microsoft.com/en-us/accessibility/powerpoint/use-keyboard-shortcuts-to-create-powerpoint-presentations) |


Google 검색은 Chrome 목록이 아닙니다. Google 검색 페이지 자체의 접근성 탐색과 Safari에서 검색·탐색하는 동작을 서로 다른 그룹에 넣었습니다. 주소창 검색은 Safari의 검색 엔진이 Google일 때 적용됩니다. 검색창 포커스 `/`와 음성 검색 조합은 현재 공식 자료와 실행 환경에서 확인하지 못해 포함하지 않았습니다. 나머지 항목에도 적용 조건과 출처를 기록했습니다. Safari의 Tab 탐색과 새 탭 열기는 설정에 따라 동작이 달라질 수 있습니다.

Google 검색과 tmux ID는 Cheatble 내부 목록 ID이며 실제 macOS 앱 번들 ID가 아닙니다. 둘 다 저장된 목록에서 직접 선택합니다. Safari URL, 브라우저 기록, 터미널 내부 명령을 수집하지 않습니다. tmux는 기본 prefix `Control+B`를 누르고 놓은 뒤 다음 키를 누릅니다. Shift로 입력하는 기호는 US 배열 기준이며 `~/.tmux.conf`에서 바꾼 값은 각 항목을 수정하세요. cmux도 기본 설정 기준입니다. 실제 cmux 번들 ID는 [공식 프로젝트 설정](https://github.com/manaflow-ai/cmux/blob/main/cmux.xcodeproj/project.pbxproj)에서 확인했습니다.

Office 목록은 각 공식 문서의 macOS 절을 기준으로 직접 구성했습니다. Windows의 Alt 리본 조합은 포함하지 않았습니다. 기능 키는 Mac 설정에 따라 Fn을 함께 눌러야 하며, Excel의 Control+Space는 입력 소스 전환과 겹칠 수 있습니다.

## 새 앱 단축키 추가하기

1. 원하는 앱을 활성화하고 Cheatble의 현재 앱 아이콘을 선택합니다.
2. 빈 목록의 **추가 요청 복사**를 누릅니다.
3. 로컬 파일과 명령 실행을 지원하는 코딩 에이전트에 붙여 넣습니다. 앱 이름·번들 ID·버전·로컬 설치 방법이 함께 복사됩니다.
4. 공식 문서나 실제 메뉴로 확인한 팩을 만들어 설치하도록 요청합니다. 실행 중인 Cheatble은 2초 주기로 변경을 확인하며 재시작 없이 반영합니다.

이 버튼은 클립보드와 로컬 Requests 파일만 작성하며 외부로 자동 전송하지 않습니다. Cheatble 자체에는 계정이나 API 키가 필요하지 않습니다. [요청문 예시](../README.ko.md#에이전트에게-팩-생성-요청하기)를 사용할 수 있으며 직접 항목을 추가하거나 JSON 파일을 설정에서 가져올 수도 있습니다.

## 팩 형식과 설치

`library.json` 내보내기와 별도의 형식입니다. 번들 예시는 `Sources/CheatbleCore/Resources/Packs/`에 있습니다.

```json
{
  "schemaVersion": 1,
  "bundleIdentifier": "com.example.app",
  "appName": "앱 이름",
  "shortcuts": [
    {
      "id": "example.action",
      "title": "실제 동작 이름으로 교체",
      "category": "기본",
      "keys": "Command+Shift+K",
      "detail": "형식 예시입니다. 확인한 실제 동작과 키로 교체하세요.",
      "aliases": ["실제 메뉴 제목"]
    }
  ]
}
```

`sourceURL`에 확인한 공식 문서의 HTTP(S) URL을 넣으세요. 동작 ID는 업데이트해도 유지해야 즐겨찾기·익힘·사용자 수정이 연결됩니다. `aliases`는 실제 메뉴 제목을 확인한 경우에만 넣습니다. 서로 다른 동작이 같은 키를 쓸 수 있으므로 키 조합만으로 같은 ID를 부여하지 마세요.

```sh
/Applications/Cheatble.app/Contents/MacOS/Cheatble --pack-example
/Applications/Cheatble.app/Contents/MacOS/Cheatble --install-pack /absolute/path/app-shortcuts.json
```

설치 위치는 `~/Library/Application Support/Cheatble/Packs/<bundleIdentifier>.json`입니다. 파일을 검증하고 원자적으로 교체하며 잘못된 입력은 기존 파일을 덮어쓰지 않습니다. JSON 한 파일 1MB·1,000항목, 전체 128파일·10MB까지 읽습니다. 오류가 있는 파일은 건너뛰고 설정에 원인을 표시합니다. 같은 앱의 팩은 한 파일로 합쳐 설치하세요. 외부 팩이 같은 범위의 번들 팩 전체를 대체하므로 업데이트할 때 유지할 항목도 포함해야 합니다. 사용자가 직접 고친 `library.json` 항목은 그대로 우선합니다.

키는 `Command+K`, `Control+B → C` 형식입니다. 각 키캡을 따로 표시하며, ` → `는 동시 입력이 아닌 순차 입력입니다. `Left/Right/Up/Down`, `Return`, `Space`, `Tab`, `Escape`, `Delete`, `PageUp/PageDown`, `F1`–`F20`을 지원합니다. 더하기 문자 키는 `Plus`로 적습니다.

## 저장된 실제 앱 메뉴

권한을 허용해 읽은 앱 메뉴는 `library.json`의 `apps`에 저장합니다. 일부 메뉴만 읽혔다면 이전 메뉴와 합쳐 보존합니다. 상단 세 번째 아이콘 옆 ∨를 열어 아이콘 격자에서 선택하며, 검색과 스크롤을 지원합니다. 현재 활성 앱은 첫 아이콘으로 볼 수 있어 드롭다운에 중복 표시하지 않습니다. 저장된 앱을 선택하면 다른 앱으로 전환해도 목록·검색·필터를 유지하고 첫 아이콘만 현재 앱에 맞춰 바뀝니다. 앱이 실행 중이지 않아도 볼 수 있습니다. 저장된 메뉴는 마지막으로 읽은 값이므로 실제 앱에서 변경된 키는 해당 앱을 다시 활성화해 갱신하세요.
