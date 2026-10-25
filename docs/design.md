# Cheatble의 회색 시스템 테마

Apple Human Interface Guidelines의 [색상](https://developer.apple.com/design/human-interface-guidelines/color)과 [SF Symbols](https://developer.apple.com/sf-symbols/)를 참고합니다.

- 배경: AppKit `windowBackgroundColor`.
- 본문·선택 강조: `labelColor`, 보조 설명: SwiftUI `secondary`.
- 선택 배경: 본문색의 낮은 불투명도. 라이트·다크 모드에서 의미 색상을 유지합니다.
- 경고와 오류는 의미를 전달하는 시스템 색상을 유지합니다.
- 조작 아이콘은 SF Symbols, 키는 일정 크기의 개별 키캡입니다. 설치된 다른 앱은 식별을 위해 그 앱의 원본 아이콘을 사용하며, 내장 목록용 대체 아이콘은 회색 바탕과 흰색 기호로 맞춥니다.
- 앱 상단과 설정은 번들의 같은 `AppIcon.icns`를 읽습니다. Dock도 같은 파일을 사용합니다.
- 앱 아이콘은 회색 키보드·단축키 시트 형태이며 [원본 PNG](../Resources/AppIcon.png)를 사용합니다.

상단의 앱 이름은 아이콘 오른쪽에 표시합니다. 카테고리 높이는 26pt이며 빈 공간까지 눌러 접고 펼칩니다. 접힌 단축키 행에는 관리 버튼을 표시하지 않고, 펼친 상세 영역에 즐겨찾기·공부 완료 버튼과 수정을 위한 연필 아이콘을 표시합니다. 앱별 단축키 설정에서도 관리할 수 있습니다. 596pt 너비부터 2단, 888pt부터 3단을 사용하며 최대 3단입니다.

오버레이의 최소 너비는 240pt입니다. 상단 필터 6개는 각각 29×25pt, 간격 5pt로 나란히 배치하며 총 개수는 표시하지 않습니다.
