# OmniIsland

[OmniWM](https://github.com/OmniNull/OmniWM)용 다이나믹 아일랜드 스타일 macOS 앱입니다.

- 평소에는 보이지 않습니다. 노치가 있는 화면에서는 노치와 같은 검은 모양으로 숨어 있고, 노치가 없는 화면에서는 완전히 사라집니다.
- **Option(⌥) 키를 누르고 있으면** 노치에서 아래로 바가 내려오면서 현재 모니터의 워크스페이스 목록과 포커스된 앱을 보여 줍니다.
- **워크스페이스 전환이나 창 이동이 실제로 일어나면** 바가 스프링 애니메이션으로 한 번 더 펼쳐지면서 "어디에서 어디로" 이동했는지 보여 줍니다.
- 애니메이션 종류와 속도, 색상, 크기, 트리거 키는 모두 설정 파일로 바꿀 수 있고, 파일을 저장하면 바로 반영됩니다.

OmniWM 내장 워크스페이스 바와 달리 macOS의 "동작 줄이기"나 OmniWM 애니메이션 설정과 상관없이 동작합니다.

- **⌥H를 누르면** 아일랜드가 펼쳐지면서 검색창이 열립니다. 바로 입력하면 앱, OmniWM에 열려 있는 창, 계산 결과가 아일랜드 아래로 붙습니다. `c`, `w`, `s` 다음에 스페이스를 누르면 클립보드 관리자, 창 관리자, 설정 관리자로 바로 들어갑니다. 자주 여는 주소는 Quick Links로 저장해 `gh owner/repo`처럼 키워드로 엽니다. 자세한 내용은 아래 [런처](#런처)를 보세요.

## 요구 사항

- macOS 14 이상 (macOS 26 Tahoe, Apple Silicon에서 사용하는 것을 기준으로 작성했습니다)
- Xcode 16 이상 또는 Swift 5.10 이상의 Command Line Tools
- OmniWM, 그리고 OmniWM 메뉴 막대 메뉴에서 켠 **Enable IPC**
- `omniwmctl` (OmniWM 메뉴의 **Install CLI to PATH**로 설치하거나, 앱 안의 `OmniWM.app/Contents/MacOS/omniwmctl`을 그대로 사용합니다)

## 설치와 업데이트 (Homebrew)

```bash
brew tap jadewisemann/dynamic-island https://github.com/jadewisemann/dynamic-island
brew install --cask omni-island     # /Applications/OmniIsland.app
brew upgrade --cask omni-island     # 새 버전이 나오면 같은 자리에 덮어씁니다
```

- 이 저장소의 `Casks/omni-island.rb`가 cask 정의입니다. `v0.2.0`처럼 `v`로 시작하는 태그를 푸시하거나, Actions 탭에서 Build 워크플로를 수동으로 실행하면서 `release` 칸에 `0.2.0`처럼 버전을 적으면 GitHub Actions가 태그와 릴리스를 만들고, cask의 버전과 해시도 `main`에 자동으로 갱신합니다. 그래서 `brew upgrade`만 하면 새 버전을 받을 수 있습니다.
- 앱은 Apple 공증을 받지 않았으므로, cask가 설치 직후 격리 속성(`com.apple.quarantine`)을 지우고 앱을 실행합니다.
- 앱 버전은 태그에서, 빌드 번호는 커밋 수에서 정해집니다. 메뉴 막대 메뉴 맨 위에서 확인할 수 있습니다.

### nightly 채널

`main`에 커밋이 올라올 때마다 GitHub Actions가 앱을 빌드해서 `nightly` 프리릴리스에 올리고, `omni-island@nightly` cask의 버전과 해시를 갱신합니다. 버전은 `0.5.0-nightly.123`처럼 마지막 태그 뒤에 커밋 수가 붙는 형태입니다.

```bash
# 안정 버전 → nightly
brew uninstall --cask omni-island && brew install --cask omni-island@nightly

# nightly → 안정 버전
brew uninstall --cask omni-island@nightly && brew install --cask omni-island

# nightly 최신으로 올리기
brew update && brew upgrade --cask omni-island@nightly
```

- 두 cask는 같은 `/Applications/OmniIsland.app`을 설치하므로 동시에 설치할 수 없습니다. 그래서 먼저 지우고 설치합니다.
- 두 채널 모두 같은 인증서로 서명하므로, 전환해도 손쉬운 사용 권한과 `~/.config/omni-island` 설정은 그대로 유지됩니다. (`--zap`을 붙이면 설정이 지워지니 주의하세요.)
- `nightly` 릴리스에는 최근 빌드 5개만 남겨 둡니다.

### 권한이 매번 초기화되지 않게 하기 (한 번만 설정)

macOS는 손쉬운 사용 권한을 앱의 **서명**에 묶어서 기억합니다. 서명이 빌드마다 달라지면(ad-hoc 서명) 업데이트할 때마다 권한을 다시 줘야 합니다. 모든 빌드를 같은 인증서로 서명하면 권한이 그대로 유지됩니다.

Mac에서 한 번만 실행합니다.

```bash
brew install gh && gh auth login     # 이미 로그인되어 있으면 건너뜁니다
scripts/create-signing-cert.sh
```

이 스크립트는 다음 일을 합니다.

1. 자체 서명 코드 서명 인증서 "OmniIsland Signing"을 만듭니다 (유효 기간 20년).
2. 로그인 키체인에 넣어서, 로컬의 `scripts/bundle.sh`도 같은 인증서로 서명하게 합니다.
3. GitHub Actions 비밀 값 `MACOS_CERT_P12`, `MACOS_CERT_PASSWORD`를 저장합니다. `gh`가 없으면 직접 넣을 값을 출력합니다.
4. 백업을 `~/.omni-island-signing`에 남깁니다. 이 폴더는 비공개로 보관하세요.

설정 후 처음 설치할 때 권한을 한 번 더 허용하면, 그 뒤로는 업데이트해도 다시 묻지 않습니다. 비밀 값이 없으면 CI는 일회용 인증서로 서명하고 경고를 남깁니다.

## 소스에서 빌드하기

```bash
git clone https://github.com/jadewisemann/dynamic-island.git
cd dynamic-island

# OmniWM 없이 애니메이션만 먼저 확인하기 (가짜 워크스페이스 5개)
swift run OmniIsland --demo

# 앱 번들로 만들어 /Applications에 설치하고 실행하기
scripts/bundle.sh --install
```

`bundle.sh`는 키체인에 "OmniIsland Signing" 인증서가 있으면 그것으로 서명하고, 없으면 ad-hoc으로 서명합니다.

처음 실행하면 **손쉬운 사용(Accessibility)** 권한을 요청합니다. 시스템 설정 → 개인정보 보호 및 보안 → 손쉬운 사용에서 OmniIsland를 켜 주세요.

- 권한이 없어도 동작은 합니다. 이 경우 Option 키 상태를 초당 40회 읽는 방식으로 대신 감지하고, 권한이 허용되면 자동으로 이벤트 기반 감지로 바뀝니다. 알림 배지는 권한이 있어야 보입니다.
- 로그인할 때 자동으로 실행하려면 시스템 설정 → 일반 → 로그인 항목에 `/Applications/OmniIsland.app`을 추가합니다.

Xcode에서 작업하고 싶다면 `open Package.swift`로 열면 됩니다.

## 동작 방식

```
omniwmctl subscribe active-workspace,focus,windows-changed,layout-changed \
          --reconnect --format ndjson
        │  (한 줄에 JSON 하나)
        ▼
OmniWMClient ── WMStateTracker ──(스냅숏 비교로 이동 감지)── IslandModel ── SwiftUI
                                                               ▲
                                    ModifierMonitor (Option) ──┘
```

- OmniWM 구독 채널은 이벤트 로그가 아니라 최신 상태 스냅숏을 보내 주는 스트림입니다. 그래서 앞뒤 스냅숏을 비교해서 이동을 찾아냅니다.
  - **워크스페이스 전환**: `active-workspace`에서 같은 디스플레이의 활성 워크스페이스가 바뀌었을 때입니다.
  - **창 이동**: `windows-changed` 스냅숏에서 같은 창 id의 워크스페이스가 바뀌었을 때입니다. 여러 창이 동시에 옮겨지면 포커스된 창을 대표로 보여 줍니다.
  - 창을 옮기면서 워크스페이스도 따라 바뀌는 경우처럼 140ms 안에 이벤트가 겹치면, 정보가 더 많은 "창 이동" 하나로 합칩니다.
- `--reconnect` 덕분에 OmniWM이 재시작되어도 다시 연결합니다. 처음 연결에 실패하면(IPC가 꺼져 있는 경우 등) 1초부터 30초까지 간격을 늘려 가며 다시 시도합니다.
- Option 키로 연 워크스페이스 줄에서 앱 아이콘을 누르면 `omniwmctl window navigate`로 그 창으로 이동합니다(필요하면 워크스페이스도 바뀝니다). 워크스페이스 이름이나 번호를 누르면 그 워크스페이스로 전환합니다. 마우스가 아일랜드 위에 있는 동안에는 Option 키를 떼도 닫히지 않습니다.
- 마우스를 아일랜드 위쪽 화면 끝(숨은 아일랜드 양옆 24pt까지)에 잠깐 대면 Option 키 없이도 워크스페이스 줄이 열립니다. 이렇게 연 줄에서도 앱 아이콘을 한 번 누르면 바로 그 창으로 이동하고, 마우스가 아일랜드를 벗어나면 닫힙니다.
- 메뉴 막대를 자동으로 숨겨 두었다면 화면 끝에 마우스를 댈 때 메뉴 막대도 함께 내려옵니다. macOS에는 다른 앱의 메뉴 막대 표시를 막는 공개 API가 없어서, `behavior.blockMenuBar`로 정한 구간에서는 마우스가 맨 위 한 줄에 닿는 순간 1pt 아래로 되돌려 놓는 방식으로 막습니다. 기본값은 노치가 없는(가상 노치) 화면의 아일랜드 주변만 막으므로, 그 화면에서도 다른 위치의 위쪽 끝에서는 메뉴 막대를 그대로 쓸 수 있습니다.
- 워크스페이스 줄이 열려 있을 때 Option을 누른 채 아일랜드를 끌면 원하는 자리로 옮길 수 있습니다. 4pt 넘게 끌어야 이동으로 보므로, Option을 누른 채 짧게 누르면 지금처럼 클릭으로 동작합니다. 옮긴 위치는 화면마다 기억하고, 메뉴 막대 아이콘 → "아일랜드 위치 되돌리기"로 원래 자리로 돌아옵니다.
- 플로팅 창은 타일 창 뒤에 얇은 구분선을 두고, 점선 테두리와 조금 작은 아이콘으로 표시합니다.
- 아일랜드 창은 평소에는 클릭을 통과시키는 투명 패널이며(워크스페이스 줄이 열려 있고 마우스가 아일랜드 위에 있을 때만 클릭을 받습니다), 메뉴 막대보다 위 레벨에 떠서 모든 Space와 전체 화면 앱 위에 나타납니다. 키보드 포커스를 가져가지 않습니다.
- 노치 크기는 `NSScreen.safeAreaInsets`와 `auxiliaryTopLeftArea/RightArea`로 계산합니다. 노치가 없는 화면에서는 `fallbackNotchWidth`와 메뉴 막대 높이를 사용합니다.

## 설정

메뉴 막대의 캡슐 아이콘 → **설정…**(⌘,)을 누르면 설정 창이 열립니다. 일반, 테마, 레이아웃, 표시 요소, 애니메이션, 연결 탭에서 값을 바꾸면 창 위쪽의 미리보기와 실제 아일랜드에 바로 반영되고 설정 파일에도 저장되므로, 파일을 직접 고칠 필요는 없습니다. 처음 실행할 때와, 메뉴 막대 아이콘을 숨긴 상태에서 앱을 다시 열 때에도 설정 창이 나타납니다.

설정 창이 저장하는 파일은 `~/.config/omni-island/config.json`입니다. 처음 실행할 때 주석이 달린 기본 파일이 만들어지고, 메뉴 막대 아이콘 → "설정 파일 열기"로 바로 열 수 있습니다. JSON5 형식이라 `//` 주석과 끝 쉼표를 쓸 수 있으며, 적지 않은 항목은 기본값을 사용합니다.

| 키 | 기본값 | 설명 |
|---|---|---|
| `omniwmctlPath` | `""` | `omniwmctl` 경로입니다. 비워 두면 PATH, `~/.local/bin`, `/opt/homebrew/bin`, `/Applications/OmniWM.app/Contents/MacOS`에서 찾습니다. |
| `socketPath` | `""` | OmniWM 소켓 경로를 바꿨다면 적습니다 (`OMNIWM_SOCKET`). |
| `trigger.modifier` | `"option"` | `option`, `leftOption`, `rightOption`, `command`, `control`, `shift` 등이며 `"control+option"`처럼 조합할 수 있습니다. |
| `trigger.holdDelayMs` | `120` | 이 시간 이상 누르고 있어야 나타납니다. Option으로 특수 문자를 입력할 때 깜빡이는 것을 줄여 줍니다. |
| `trigger.hideDelayMs` | `160` | 키를 뗀 뒤 사라질 때까지의 시간입니다. |
| `trigger.exactMatch` | `true` | 다른 modifier가 함께 눌려 있으면 나타나지 않습니다. |
| `trigger.allowShift` | `true` | `exactMatch`가 켜져 있어도 Shift는 함께 눌러도 됩니다. Option+Shift+숫자처럼 OmniWM 단축키를 누르는 중에도 아일랜드가 보입니다. |
| `behavior.showEventsWithoutModifier` | `true` | 키를 누르지 않았을 때 일어난 이동도 펼쳐서 보여 줍니다. |
| `behavior.eventDurationMs` | `1700` | 펼쳐진 상태가 유지되는 시간입니다. |
| `behavior.showWorkspaceSwitch` / `showWindowMove` | `true` | 이벤트 종류별로 켜고 끕니다. |
| `behavior.windowMoveTrail` | `true` | 창이 다른 워크스페이스로 옮겨지면 워크스페이스 줄에서 작은 방울이 원래 워크스페이스에서 새 워크스페이스로 흘러갑니다. 방울에는 아이콘을 따로 싣지 않아서 잔상이 남지 않습니다. 줄이 보일 때(`layout.eventPlacement`가 `replace`가 아닐 때나 트리거 키를 누르고 있을 때) 나타납니다. |
| `behavior.showEmptyWorkspaces` | `false` | 창이 없는 워크스페이스도 목록에 보여 줍니다. |
| `behavior.screen` | `"notch"` | `notch`(노치 있는 화면), `main`(메뉴 막대 화면), `active`(OmniWM이 조작 중인 모니터) 중 하나입니다. |
| `behavior.hiddenStyle` | `"auto"` | `notch`는 숨었을 때 노치 크기의 검은 모양을 남기고, `fade`는 완전히 사라집니다. `auto`는 화면에 노치가 있는지 보고 고릅니다. |
| `behavior.coalesceMs` | `140` | 이 시간 안에 겹친 이벤트를 하나로 합칩니다. |
| `behavior.revealOnHover` / `hoverDelayMs` | `true` / `150` | 마우스를 아일랜드 위쪽 화면 끝에 이 시간만큼 대고 있으면 워크스페이스 줄을 엽니다. |
| `behavior.blockMenuBar` | `"virtualNotch"` | 자동으로 숨긴 메뉴 막대가 내려오지 않게 막는 범위입니다. `virtualNotch`는 노치 없는 화면의 아일랜드 주변, `island`는 모든 화면의 아일랜드 주변, `screen`은 아일랜드가 있는 화면의 위쪽 끝 전체, `off`는 막지 않습니다. |
| `behavior.dragToMove` | `true` | 워크스페이스 줄이 열려 있을 때 Option을 누른 채 끌어서 아일랜드를 옮깁니다. |
| `appearance.showEventProgress` | `true` | 펼쳐진 상태가 끝날 때까지 남은 시간을 아래쪽 막대로 보여 줍니다. |
| `appearance.workspaceStyle` | `"apps"` | `apps`는 워크스페이스 번호 옆에 그 워크스페이스의 앱 아이콘을 나열하고(OmniWM 워크스페이스 바와 비슷합니다), `pills`는 번호만 보여 줍니다. |
| `appearance.appIconSize` / `maxAppsPerWorkspace` | `20` / `6` | 앱 아이콘 크기와 워크스페이스마다 보여 줄 최대 아이콘 수입니다. 넘치는 앱은 `+N`으로 묶습니다. |
| `appearance.showBadges` | `true` | Dock 아이콘의 빨간 알림 배지를 앱 아이콘에도 표시합니다. 손쉬운 사용 권한이 필요하며, `behavior.badgeIntervalMs`(기본 3000) 간격으로 다시 읽습니다. |
| `appearance.highlightFocusedWindow` | `true` | 지금 포커스된 창의 앱 아이콘을 강조색 테두리로 감싸서 표시합니다. 포커스가 옮겨지면 테두리도 따라 이동합니다. |
| `appearance.multiWindowStyle` | `"dots"` | 한 워크스페이스에 창이 여러 개 있는 앱을 보여 주는 방식입니다. `merge`는 아이콘 하나로 합치고, `dots`는 아이콘 아래에 창 개수만큼 점(최대 3개)을 찍고, `separate`는 창마다 아이콘을 따로 표시합니다. |
| `appearance.backgroundStyle` | `"solid"` | `solid`(단색), `material`(macOS 반투명 재질), `gradient`(`backgroundColor`에서 `gradientColor`로, `gradientAngle` 방향) 중 하나입니다. 반투명 재질의 두께는 `material`(`thin`, `regular`, `thick`)로 정합니다. |
| `appearance.activeTextColor` / `fillColor` | `"#FFFFFF"` | 활성 워크스페이스 위의 글자 색과, 비활성 칸·창 개수 점·테두리에 옅게 쓰는 기본 색입니다. 밝은 테마에서는 `fillColor`를 검정으로 둡니다. |
| `appearance.badgeColor` / `badgeTextColor` / `progressColor` | | 알림 배지와 남은 시간 막대의 색입니다. `progressColor`를 비워 두면 강조색을 씁니다. |
| `appearance.activeStyle` / `activeGlow` | `"fill"` / `true` | 활성 워크스페이스 표시 방식(`fill`, `outline`, `underline`, `dot`)과 빛 번짐 여부입니다. |
| `appearance.fontFamily` / `fontDesign` / `fontWeight` / `numberFontDesign` | `""` / `"default"` / `"regular"` / `"rounded"` | 설치된 글꼴 이름(비우면 시스템 글꼴), 시스템 글꼴 모양(`default`, `rounded`, `monospaced`, `serif`), 전체 굵기(`light`, `regular`, `bold`, `heavy`), 워크스페이스 번호 글꼴(`same`이면 본문과 같음)입니다. |
| `appearance.*` | | 그 밖에 배경색과 불투명도, 강조색, 글자색, 테두리, 그림자, 모서리 반경, 글자 크기, 알약 크기, 펼친 너비와 높이가 있습니다. 색상은 `#RRGGBB` 또는 `#RRGGBBAA`로 적습니다. |
| `theme.mode` | `"fixed"` | `system`이면 macOS가 다크 모드일 때 `appearance`의 색을, 라이트 모드일 때 `theme.light`의 색을 씁니다. `theme.light`에는 `appearance`와 같은 색 키를 적습니다. |
| `theme.saved` | `[]` | 설정 창에서 "내 테마"로 저장한 테마 목록입니다. |
| `layout.shape` | `"attached"` | `attached`는 노치에서 자라나고, `floating`은 메뉴 막대 아래 `layout.topGap`만큼 떨어진 캡슐로 나타납니다. |
| `layout.horizontalPosition` / `horizontalOffset` | `"center"` / `0` | 노치가 없는 화면에서 가로 위치(`center`, `left`, `right`)와 미세 조정 값입니다. |
| `layout.widthMode` / `fixedWidth` | `"auto"` / `420` | `fixed`이면 아일랜드가 적어도 `fixedWidth`만큼 넓어집니다. |
| `layout.rowAlignment` / `contentPadding` | `"center"` / `20` | 워크스페이스 줄 정렬(`center`, `leading`, `spread`)과 안쪽 여백입니다. |
| `layout.eventPlacement` | `"below"` | 이동 알림을 워크스페이스 줄 아래(`below`), 위(`above`), 또는 줄 대신(`replace`) 보여 줍니다. |
| `widgets.leftWing` / `rightWing` | `"app"` / `"workspace"` | 노치 양옆에 보여 줄 내용입니다. `app`, `workspace`, `clock`, `date`, `windows`, `nextEvent`(다음 일정), `notifications`(놓친 알림 수), `agents`(코딩 에이전트), `usage`(AI 사용량), `none` 중 하나입니다. |
| `widgets.leftPanel` / `rightPanel` | `["clock"]` / `["calendar"]` | 워크스페이스 줄이 보일 때 아일랜드 양옆에 붙는 정사각형 위젯 칸입니다. `clock`, `calendar`, `nextEvent`, `events`, `notifications`를 순서대로 적고, 비우면 그쪽 칸이 없습니다. |
| `widgets.panelUnits` | `1` | 한쪽 칸의 너비를 정사각형 1~3칸으로 정합니다. 2칸 이상이면 위젯이 넓은 모양(큰 시계, 2주 달력, 일정 목록)으로 바뀝니다. |
| `widgets.workspaceLabel` | `"name"` | 워크스페이스를 OmniWM 표시 이름(`name`), 번호(`number`), 번호와 이름(`both`)으로 보여 줍니다. |
| `widgets.eventIcon` / `eventSubtitle` / `eventFromTo` | `true` | 이동 알림 카드의 아이콘, 부제목, "출발 → 도착" 표시를 켜고 끕니다. |
| `widgets.clockFormat` | `"24h"` | `24h`, `12h`, `24hSeconds` 중 하나입니다. |
| `notifications.enabled` | `true` | macOS 알림 배너를 읽어 아일랜드에 카드로 보여 줍니다. 손쉬운 사용 권한이 필요합니다. |
| `notifications.readDatabase` | `true` | macOS 알림 데이터베이스도 읽습니다. 전체 디스크 접근 권한이 있어야 동작하며, 배너를 꺼 둔 앱의 알림도 볼 수 있습니다. |
| `notifications.durationMs` / `contentMode` | `4000` / `"full"` | 카드 표시 시간과 보여 줄 내용(`full`, `title`, `app`)입니다. |
| `notifications.filterMode` / `apps` | `"all"` / `[]` | `allow`는 `apps`에 적은 앱만, `block`은 그 앱을 빼고 보여 줍니다. 앱 이름이나 번들 ID를 적습니다. |
| `notifications.dismissSystemBanner` | `false` | 내용을 읽은 직후 macOS 기본 배너를 닫습니다. |
| `notifications.keepIndicator` / `indicatorTimeoutMin` | `true` / `30` | 알림 카드가 접힌 뒤에도 노치 옆에 놓친 알림 아이콘과 개수를 남깁니다. 트리거 키를 누르면 사라집니다. |
| `notifications.mergeWindowMs` | `3000` | 같은 앱에서 이 시간 안에 온 알림은 한 장으로 합칩니다. |
| `calendar.enabled` / `calendars` | `false` / `[]` | 캘린더 일정을 읽습니다. 켜면 캘린더 접근 권한을 묻습니다. 비워 두면 모든 캘린더를 씁니다. |
| `calendar.alertMinutes` / `showAlerts` / `includeAllDay` | `[5, 0]` / `true` / `false` | 일정 시작 몇 분 전에 카드를 띄울지 정합니다. |
| `dashboard.enabled` / `holdMs` / `items` | `false` / `800` / `["clock", "events", "notifications"]` | 트리거 키를 더 오래 누르면 큰 시계, 오늘 남은 일정, 최근 알림을 보여 줍니다. |
| `launcher.enabled` / `hotkey` | `true` / `"option+h"` | 런처를 켜고 끄며, 여는 단축키를 정합니다. `option+space`, `control+space`처럼 적습니다. |
| `launcher.englishInput` | `true` | 런처를 열 때 입력 소스를 영어로 바꾸고, 닫으면 원래 입력 소스로 되돌립니다 (Flow Launcher의 "항상 영어로 입력 시작"과 같습니다). |
| `launcher.maxResults` | `10` | 한 번에 보여 줄 최대 결과 수입니다. |
| `launcher.showRecent` / `recentCount` | `true` / `5` | 검색어가 없을 때 최근에 연 앱을 보여 줍니다. |
| `launcher.searchApps` / `searchWindows` / `calculator` | `true` | 검색 대상을 종류별로 켜고 끕니다. |
| `launcher.currency` / `searchSettings` | `true` | 환율 변환과 시스템 설정 패널 검색입니다. |
| `launcher.searchFiles` / `maxFiles` | `true` / `4` | 홈 폴더의 파일을 Spotlight에서 찾습니다. |
| `launcher.webSearch` / `suggestions` / `maxSuggestions` | `true` / `true` / `3` | "Google에서 검색" 줄과 추천 검색어입니다. |
| `launcher.askClaude` / `askGrok` / `searchX` | `false` | 입력한 내용을 Claude, Grok에 묻거나 X에서 찾는 줄을 붙입니다. |
| `launcher.width` | `560` | 런처가 열렸을 때 아일랜드의 너비입니다. |
| `launcher.prefixes` | `{ "clipboard": "c", "windows": "w", "settings": "s", "files": "f", "apps": "", "quicklinks": "" }` | 내장 앱의 트리거 접두어입니다. `""`이면 접두어를 쓰지 않습니다. |
| `launcher.quickLinks` | GitHub·YouTube·다운로드 폴더 예시 3개 | Quick Links 목록입니다. 항목마다 `name`, `link`, `keyword`(선택), `app`(선택)을 적습니다. 자세한 내용은 아래 [Quick Links](#quick-links)를 보세요. |
| `launcher.searchQuickLinks` | `true` | Quick Links를 기본 검색에 섞어서 보여 줍니다. |
| `launcher.searchClipboard` | `false` | 복사 기록도 기본 검색에 섞어서 보여 줍니다. |
| `launcher.learnFromPicks` | `true` | 고른 결과를 학습해서, 자주 고른 항목과 같은 검색어로 골랐던 항목을 위로 올립니다. |
| `shelf.enabled` / `maxItems` | `true` / `30` | 클립보드 관리자가 복사 기록을 남길지와 기억할 개수입니다. |
| `animation.style` | `"spring"` | `spring`, `bouncy`, `smooth`, `snappy`, `easeInOut`, `none` 중 하나입니다. |
| `animation.response` / `dampingFraction` | `0.5` / `0.9` | `spring`일 때 적용됩니다. 감쇠 값이 낮을수록 더 많이 튕깁니다. 이전 기본값(`0.45` / `0.76`)이 그대로 저장된 파일은 새 기본값으로 읽습니다. |
| `animation.durationMs` | `380` | `spring`이 아닌 스타일의 재생 시간입니다. |
| `animation.speed` | `1` | 모든 움직임의 속도 배율입니다. |
| `animation.contentTransition` | `"blur"` | 내용이 나타나는 방식입니다. `blur`, `fade`, `slide`, `none` 중 하나입니다. (예전의 `blurTransitions: false`는 `fade`로 읽습니다.) |
| `animation.popOnEvent` | `true` | 이벤트가 들어올 때 살짝 커졌다가 돌아오는 효과입니다. |
| `animation.liquid` | `true` | 끈적한 액체 효과입니다. 좌우 위젯 칸이 아일랜드와 떨어진 방울로 나뉘어, 나타날 때는 가운데에서 늘어나며 떨어져 나오고 사라질 때는 다시 녹아 들어갑니다. 이벤트로 아일랜드가 커져도 위젯 방울은 옆에 그대로 남습니다. 채우기(`fill`) 활성 표시도 다음 워크스페이스로 늘어나며 옮겨 갑니다. |

설정 창의 테마 탭에는 기본 테마 6가지와, r/unixporn 등에서 많이 쓰는 커뮤니티 테마(Catppuccin Mocha·Latte, Nord, Gruvbox, Tokyo Night, Rosé Pine·Dawn, Dracula, Everforest, Kanagawa)가 프리셋으로 들어 있습니다. 지금 색 구성을 "내 테마"로 저장하거나 `.json` 파일로 내보내고 가져올 수도 있습니다.

예를 들어 더 통통 튀는 느낌을 원하면 다음처럼 적습니다.

```json5
{
  "animation": { "style": "spring", "response": 0.5, "dampingFraction": 0.6 },
  "appearance": { "accentColor": "#FF9F0A", "expandedWidth": 440 },
}
```

## 런처

Option을 누르고 있으면 평소처럼 아일랜드가 내려오고, 이어서 H를 누르면(⌥H) 아일랜드가 넓어지면서 키보드 입력을 받습니다. 이때부터는 Option을 떼도 닫히지 않습니다. 앱은 계속 원래 쓰던 앱이 활성 상태로 남고, 아일랜드만 입력을 받습니다.

- **검색 대상** ([nanolight](https://github.com/justrach/nanolight)의 기능을 옮겼습니다)
  - 앱: `/Applications`, `/System/Applications`, `~/Applications` 등에 있는 앱입니다. 한글 이름과 영어 이름 모두, `ㄱㅅㄱ`처럼 초성으로도 찾습니다.
  - OmniWM에 열려 있는 창: 앱 이름이나 창 제목으로 찾습니다.
  - 시스템 설정 패널: "wifi", "다크 모드", "로그인 항목", "단축키"처럼 입력하면 그 패널을 바로 엽니다. "설정"을 입력하면 OmniIsland 설정도 나옵니다.
  - 파일: 홈 폴더의 파일과 폴더를 Spotlight 색인에서 찾습니다. ⌘Return을 누르면 Finder에서 보여 줍니다.
  - 계산기와 환율: `2^10*3`, `0xC00`, `100 USD to KRW`, `100달러`, `5000엔`처럼 입력합니다. 환율은 [Frankfurter](https://www.frankfurter.app)의 ECB 일일 환율이며, Return을 누르면 결과를 복사합니다.
  - 웹: 맨 아래에 "Google에서 검색" 줄과 Google 추천 검색어가 붙습니다. `github.com/x`처럼 주소를 입력하면 바로 열 수 있고, 설정에서 Claude, Grok, X 줄을 켤 수 있습니다. 추천 검색어는 입력한 글자를 Google에 보내므로 끌 수 있고, 주소처럼 보이는 입력(점, 슬래시, @)은 보내지 않습니다.
- **순위**: 이름 전체 일치, 앞부분 일치, 단어 시작 일치, 머리글자(`vsc` → Visual Studio Code), 중간 일치, 글자 순서 일치, 오타(`chorme` → Chrome) 순서로 점수를 매깁니다. 앱 이름 검색의 실행 기록은 `~/.config/omni-island/launcher-history.json`에 저장됩니다.
- **학습**: Raycast나 Alfred처럼, 런처에서 고른 결과를 기억해서 순위에 반영합니다. 앱, 창, 시스템 설정, 파일, 클립보드 등 종류와 관계없이 자주, 최근에 고른 항목일수록 위로 오르고(오래된 선택은 2주마다 절반씩 약해집니다), 같은 검색어(또는 그보다 짧게 쳤던 검색어)로 골랐던 항목은 이름이 더 비슷한 다른 항목보다도 위로 올라갈 수 있습니다. 계산기, 환율 같은 답과 웹 검색 줄의 위치는 바뀌지 않습니다. 기록은 `~/.config/omni-island/launcher-picks.json`에 저장되며, `launcher.learnFromPicks`를 `false`로 두면 학습을 끕니다.
- **검색어가 없을 때**: 최근에 연 앱 5개를 보여 줍니다. 아직 기록이 없으면 실행 중인 앱으로 채웁니다.

### 내장 앱과 트리거 접두어

런처는 여러 내장 앱(플러그인)으로 이루어져 있습니다. 위의 기본 검색은 내장 앱들의 결과를 한데 모은 것이고, 내장 앱마다 정해진 접두어를 입력한 뒤 스페이스를 누르면 그 앱만 보이는 화면으로 들어갑니다. 검색창 왼쪽에 앱 이름이 표시되고, 빈 검색창에서 ⌫ 또는 Esc를 누르면 기본 검색으로 돌아갑니다. 한글 자판 상태에서 친 `ㅊ`, `ㅈ`, `ㄴ`, `ㄹ`도 같은 접두어로 인식합니다. 접두어는 설정 → 런처에서 바꾸거나 끌 수 있습니다.

| 접두어 | 내장 앱 | 들어가면 |
|---|---|---|
| `c` | 클립보드 관리자 | 복사 기록이 최신순으로 나오고, 입력하면 그 안에서 검색합니다. Return을 누르면 원래 앱에 붙여넣고, ⌘Return은 복사만 합니다. Tab, ⇧↑↓, ⌘클릭으로 여러 개를 고르면 고른 순서대로 한꺼번에 붙여넣습니다(텍스트는 줄을 바꿔 이어 붙이고, 이미지와 파일은 하나씩 붙여넣습니다). ⌘A는 전체 선택, ⌘⌫는 삭제입니다. |
| `w` | 창 관리자 | OmniWM에 열린 창을 워크스페이스별로 보여 줍니다. Return은 그 창으로 이동, ⌘Return은 지금 워크스페이스로 불러오기입니다. |
| `s` | 설정 관리자 | OmniIsland 설정과 시스템 설정 패널만 보여 줍니다. |
| `f` | 파일 검색 | 홈 폴더의 파일을 더 많이(최대 40개) 찾습니다. |
| (없음) | 앱 | 설치된 앱 전체를 자주 연 순서로 보여 줍니다. 접두어를 정하면 쓸 수 있습니다. |
| (없음) | Quick Links | 저장한 링크 전체를 보여 줍니다. 접두어를 정하면 쓸 수 있습니다. |

기본 검색에서 `c`처럼 접두어만 입력하거나 "클립보드", "창 관리자"처럼 이름을 입력하면 그 내장 앱으로 들어가는 줄도 나옵니다. 복사 기록은 기본 검색에 섞이지 않으며, 설정에서 "클립보드 기록"을 켜면 함께 검색됩니다. 비밀번호 관리자에서 복사한 것은 기록하지 않습니다.

### Quick Links

Raycast의 Quick Links처럼, 자주 여는 주소나 폴더를 이름과 키워드로 저장해 두고 런처에서 엽니다. 설정 → 런처 → Quick Links에서 추가, 편집, 삭제합니다.

- **링크**: `https://…` 웹 주소, `github.com/x`처럼 스킴이 없는 주소(https로 엽니다), `obsidian://`, `mailto:` 같은 URL, `~/Downloads` 같은 파일·폴더 경로를 적을 수 있습니다.
- **`{query}`**: 링크에 `{query}`를 넣으면 키워드(없으면 이름) 다음에 스페이스를 누르고 입력한 내용이 그 자리에 들어갑니다. 예를 들어 키워드 `gh`, 링크 `https://github.com/{query}`로 저장하면 `gh jadewisemann/dynamic-island`를 입력하고 Return을 눌러 저장소를 엽니다. 웹 주소에서는 입력한 내용을 URL 인코딩하되 `/`는 그대로 둡니다.
- **키워드만 입력**: `gh`만 입력하면 그 링크가 맨 위에 나오고, Return을 누르면 `{query}` 앞부분(`https://github.com/`)을 엽니다. `{query}`가 `?q={query}`처럼 주소의 검색어 부분에 있으면 그 사이트의 첫 화면을 엽니다. Tab을 누르면 검색창이 `gh `로 바뀌어 바로 이어서 입력할 수 있습니다.
- **힌트**: `g`처럼 키워드의 앞부분만 입력해도 그 키워드를 가진 링크가 앱보다 위에 나오고, 오른쪽 키워드 배지에서 입력한 글자가 강조됩니다. Tab을 누르면 키워드를 다음 단어까지 완성합니다.
- **계층형 키워드**: 키워드를 `gh bb stg`처럼 여러 단어로 적으면 폴더처럼 내려갈 수 있습니다. `gh `를 입력하면 `gh`로 시작하는 링크(`gh bb stg`, `gh bb prod` 등)가 모두 나오고, `gh bb `, `gh bb stg` 순서로 좁혀 갑니다. 같은 `gh` 아래에 `{query}` 링크가 있으면, 입력한 내용이 하위 키워드와 맞을 때는 하위 링크가 먼저 나오고 그렇지 않으면 `{query}` 링크로 엽니다.
- **열 앱**: 앱 이름(`Safari`), 번들 ID(`com.google.Chrome`), `.app` 경로를 적으면 기본 앱 대신 그 앱으로 엽니다.
- ⌘Return은 열지 않고 완성된 주소만 복사합니다. 내장 앱의 접두어(`c`, `w` 등)와 같은 키워드는 접두어가 먼저 적용되니 다른 키워드를 쓰세요.

```json5
"quickLinks": [
  { "name": "GitHub 저장소", "link": "https://github.com/{query}", "keyword": "gh" },
  { "name": "Bitbucket 스테이징", "link": "https://bitbucket.org/team/app/branch/staging", "keyword": "gh bb stg", "app": "Arc" },
  { "name": "다운로드 폴더", "link": "~/Downloads", "keyword": "dl" },
  { "name": "사내 위키", "link": "wiki.example.com/search?q={query}", "keyword": "wk", "app": "Safari" },
],
```

| 키 | 동작 |
|---|---|
| ⌥H | 열기와 닫기 |
| ↑ ↓, ⌃P ⌃N | 선택 이동 |
| Return | 앱 열기, 창으로 이동, 계산 결과 복사 |
| ⌘Return | 앱은 Finder에서 보기, 창은 지금 워크스페이스로 불러오기 |
| ⌘1 – ⌘9 | 해당 줄 바로 실행 |
| Tab, → (커서가 끝에 있을 때) | 첫 번째 결과의 이름으로 자동 완성. 내장 앱 줄에서는 그 앱으로 들어가기 |
| 접두어 + Space | 내장 앱으로 들어가기 (위 표 참고) |
| ⌫ (빈 검색창) | 내장 앱에서 나오기 |
| Esc | 고른 항목 해제, 검색어 지우기, 내장 앱에서 나오기, 닫기 순서로 동작 |

다른 앱이나 창을 클릭해도 런처가 닫힙니다. 단축키는 Carbon 핫키로 등록하므로 손쉬운 사용 권한이 없어도 동작하고, ⌥H가 다른 앱에 "˙"로 입력되지도 않습니다. OmniWM에서 같은 단축키를 쓰고 있다면 설정 → 런처에서 단축키를 바꿔 주세요.

## 알림과 일정

macOS에는 다른 앱의 알림을 읽는 공식 API가 없어서, 두 가지 경로를 함께 씁니다.

- **알림 배너 관찰**: 알림 배너를 그리는 `NotificationCenter` 프로세스를 손쉬운 사용 API로 관찰해서, 배너가 뜨는 순간 앱 이름, 제목, 본문을 읽습니다. 추가 권한이 필요 없지만, 배너가 뜨지 않는 알림은 읽을 수 없습니다.
- **알림 데이터베이스**: macOS가 알림을 기록하는 데이터베이스(`~/Library/Group Containers/group.com.apple.usernoted/db2/db`)를 1.5초마다 읽습니다. 시스템 설정 → 개인정보 보호 및 보안 → 전체 디스크 접근 권한에서 OmniIsland를 켜야 동작합니다. 형식이 공개되어 있지 않아서 macOS 업데이트 후 동작하지 않을 수 있습니다.
- 두 경로가 같은 알림을 보면 20초 안의 같은 내용은 한 번만 보여 줍니다.
- 데이터베이스 파일이 바뀌는 순간을 감지해서 바로 읽고, 1초 주기 확인은 보조로만 씁니다. 배너 관찰도 0.75초마다 확인합니다.
- **오른쪽 macOS 배너 없애기**: 데이터베이스 읽기를 켜 둔 상태에서 시스템 설정 → 알림 → 앱마다 알림 스타일을 "없음"으로 바꾸면 배너는 뜨지 않고, 알림은 알림 센터와 아일랜드에 그대로 들어옵니다. 앱별 설정을 바꾸고 싶지 않다면 설정의 "macOS 기본 배너 닫기"를 켭니다. 이 경우 배너가 잠깐 보였다가 닫힙니다.
- **알림 닫기**: 카드 오른쪽 위의 ×를 누르면 그 알림만 닫고 다음 알림으로 넘어갑니다. 기다리는 알림이 있으면 **모두 닫기** 버튼이 함께 나타나며, 누르면 대기 중인 알림과 노치 옆의 놓친 알림 표시, 화면 오른쪽에 남은 시스템 배너까지 한꺼번에 닫습니다.
- **지난 알림 다시 보기**: 알림 카드를 누르면 그 앱이 열리고, 카드에 마우스를 올려 두면 닫히지 않습니다. 받은 알림은 최근 30개까지 기억해서 대시보드(Option 길게 누르기, `dashboard.enabled`)와 메뉴 막대 아이콘의 "최근 알림"에서 다시 볼 수 있습니다. 항목을 누르면 해당 앱이 열립니다.
- 배너 판독이 맞지 않으면 메뉴 막대 아이콘 → 알림 → "알림 배너 구조 기록 (1분)"을 누릅니다. 테스트 알림을 보내고 1분 동안 권한 상태, 데이터베이스 상태, 배너 구조를 `~/Library/Logs/OmniIsland/notification-banners.log`에 남긴 뒤 Finder로 보여 줍니다. 평소 동작 기록은 `~/Library/Logs/OmniIsland/omni-island.log`에 남습니다.

### 권한 설정 도우미

처음 실행하거나 필요한 권한이 빠져 있으면 "OmniIsland 권한 설정" 창이 열립니다. 손쉬운 사용(필수), 전체 디스크 접근(알림 데이터베이스용), 캘린더를 한 단계씩 안내하고, 각 단계에서 해당 시스템 설정 화면을 바로 엽니다. 권한이 켜지면 자동으로 다음 단계로 넘어갑니다. macOS는 전체 디스크 접근 권한을 앱이 직접 요청할 수 없으므로, 이 단계에서는 목록에서 OmniIsland를 켜거나 "Finder에서 앱 보기"로 연 앱을 목록으로 끌어다 놓아야 합니다. 건너뛴 선택 권한은 다음 실행 때 다시 묻지 않으며, 메뉴 막대 아이콘의 "권한 설정…"에서 언제든 다시 열 수 있습니다.

일정은 EventKit으로 읽습니다. 설정 창의 "알림·일정" 탭에서 캘린더를 켜면 macOS가 캘린더 접근 권한을 묻습니다. 노치 양옆 위젯을 "다음 일정"으로 바꾸면 다음 일정과 남은 시간이 보이고, 일정이 시작되기 전에는 알림 카드가 펼쳐집니다.

## 코딩 에이전트와 외부 알림

### Claude Code·Codex 상태

설정 창의 **에이전트** 탭(또는 메뉴 막대 아이콘 → "Claude Code 훅 설치")에서 훅을 설치하면, Claude Code 세션의 상태가 아일랜드에 나타납니다.

- **권한 요청**: Claude Code가 도구 실행 허락을 구하면 아일랜드가 펼쳐지고 **허용**·**거부** 버튼이 붙은 카드가 뜹니다. `agents.approvalTimeoutSec`(기본 120초) 안에 누르지 않으면 카드가 닫히고 터미널에서 평소처럼 묻습니다. 터미널에서 먼저 답하면 카드도 닫힙니다.
- **입력 대기와 완료**: 세션이 입력을 기다리거나 답을 마치면 짧은 카드를 띄웁니다. 완료 카드에는 마지막 답변의 첫 줄이 나옵니다.
- **터미널 창으로 이동**: 카드나 위젯을 누르면 `omniwmctl window navigate`로 그 세션이 돌고 있는 터미널 창으로 이동합니다. 훅 프로세스의 부모 프로세스를 따라 올라가서 OmniWM 창을 찾고, tmux처럼 찾을 수 없으면 터미널 앱을 앞으로 가져옵니다.
- **위젯**: `widgets.leftWing`/`rightWing`에 `agents`를 넣으면 노치 옆에 세션마다 상태 점(파랑 작업 중, 노랑 입력 대기, 주황 승인 필요, 초록 완료)과 가장 급한 세션의 프로젝트 이름이 보입니다. `leftPanel`/`rightPanel`에 `agents`를 넣으면 위젯 칸에 세션 목록이 나옵니다.
- 훅 설치는 `~/.claude/settings.json`의 `hooks`에 OmniIsland 항목만 추가하고, 바꾸기 전 파일을 `settings.json.omni-island-backup`으로 남깁니다. 이미 실행 중인 세션은 다시 시작해야 적용됩니다. OmniIsland가 꺼져 있으면 훅은 아무것도 하지 않고 바로 끝납니다.
- **Codex**: `~/.codex/config.toml`에 `notify = ["/Applications/OmniIsland.app/Contents/MacOS/OmniIsland", "hook", "codex"]`를 넣으면 답을 마칠 때 알립니다.

| 키 | 기본값 | 설명 |
|---|---|---|
| `agents.enabled` | `true` | 훅 이벤트를 받아 보여 줍니다. |
| `agents.approvals` / `approvalTimeoutSec` | `true` / `120` | 권한 요청에 버튼을 띄우는지와, 응답을 기다리는 시간입니다. |
| `agents.notifyDone` / `notifyWaiting` | `true` / `true` | 완료와 입력 대기 카드를 띄웁니다. |
| `agents.cardDurationMs` / `keepDoneMin` | `5000` / `30` | 카드 표시 시간과, 끝난 세션을 위젯에 남겨 두는 시간(분)입니다. |

### AI 사용량

노치 옆 날개(`widgets.leftWing`/`rightWing`), 좌우 위젯 칸(`leftPanel`/`rightPanel`), 대시보드(`dashboard.items`)에 `usage`를 넣으면 Claude Code 사용량이 보입니다.

- **토큰 수**: `~/.claude/projects`(그리고 `CLAUDE_CONFIG_DIR`)에 Claude Code가 남기는 대화 기록을 읽어서 지금 5시간 세션과 오늘 쓴 토큰을 셉니다. 네트워크를 쓰지 않습니다.
- **요금제 한도**: `usage.planLimits`가 켜져 있으면, 키체인에 저장된 Claude Code 로그인으로 Claude Code의 `/usage` 화면과 같은 곳에서 5시간·주간 한도 사용률(%)과 리셋 시각을 5분마다 가져옵니다. 로그인이 없거나 만료되었으면 토큰 수만 보여 줍니다.

| 키 | 기본값 | 설명 |
|---|---|---|
| `usage.enabled` | `true` | 사용량을 읽습니다. `usage` 위젯을 넣었을 때만 동작합니다. |
| `usage.planLimits` | `true` | 요금제 한도(%)도 가져옵니다. |
| `usage.refreshSec` | `60` | 기록을 다시 읽는 간격(초)입니다. |

### 터미널에서 앱 열기

Homebrew로 설치하면 `omni-island` 명령이 함께 설치됩니다. VS Code의 `code`처럼, 인자 없이 입력하면 앱을 터미널과 분리해서 실행하고 바로 프롬프트로 돌아옵니다. 앱이 이미 실행 중이면 설정 창을 앞으로 가져옵니다.

```bash
omni-island            # 앱 열기 (실행 중이면 설정 창)
omni-island settings   # 설정 창 열기 (꺼져 있으면 먼저 실행)
omni-island launcher   # 런처 열기/닫기 (단축키와 같은 동작)
omni-island quit       # 앱 종료
omni-island run        # 터미널에 붙은 채로 실행 (로그가 stderr로 나옵니다)
```

### 스크립트에서 카드 띄우기

`omni-island` 명령으로 카드를 띄울 수도 있습니다. 앱이 `~/Library/Application Support/OmniIsland/island.sock`에서 요청을 받으므로, 빌드 스크립트나 텔레그램·디스코드 봇 중계, CI 결과 확인처럼 어디서든 카드를 띄울 수 있습니다.

```bash
omni-island notify --title "빌드 완료" --body "3분 12초" --icon hammer --color "#30D158"
omni-island notify --id upload --title "업로드 중" --progress 0.4   # 같은 id로 다시 보내면 내용만 바뀝니다
omni-island dismiss --id upload
omni-island help
```

`--app`(보낸 곳 이름), `--bundle-id`(그 앱 아이콘 사용), `--duration`(초)도 쓸 수 있습니다. 소켓에 한 줄짜리 JSON(`{"type":"notify","title":"…"}`)을 직접 보내도 됩니다.

## 문제 해결

- **메뉴에 "OmniWM IPC에 연결할 수 없습니다"가 보입니다**: OmniWM 메뉴에서 **Enable IPC**를 켰는지 확인합니다. 켜면 앱이 알아서 다시 연결합니다.
- **"omniwmctl을 찾지 못했습니다"가 보입니다**: GUI 앱은 셸의 PATH를 물려받지 않습니다. 설정 파일의 `omniwmctlPath`에 `which omniwmctl` 결과를 적어 주세요.
- **Option 키를 눌러도 반응이 없습니다**: 손쉬운 사용 권한을 확인하고, 설정 파일의 `trigger.modifier`가 올바른지 확인합니다. 터미널에서 `omni-island run`(직접 빌드했다면 `build/OmniIsland.app/Contents/MacOS/OmniIsland run`)을 실행하면 로그가 stderr로 출력됩니다.
- **OmniWM 버전이 바뀐 뒤 동작하지 않습니다**: OmniWM IPC는 클라이언트와 서버의 프로토콜 버전이 정확히 같아야 합니다. 이 앱은 `omniwmctl`을 거쳐 통신하므로, OmniWM과 같은 버전의 `omniwmctl`을 쓰고 있는지 확인합니다.

## 프로토타입의 한계

- GitHub Actions(macOS 15, Xcode 16.4)에서 컴파일은 확인했지만, 실제 OmniWM과 함께 동작하는지는 아직 확인하지 못했습니다.
- 워크스페이스 목록은 현재 활성 모니터의 워크스페이스만 보여 줍니다.
- 아일랜드는 클릭할 수 없습니다. 클릭해서 워크스페이스를 전환하는 기능은 다음 단계 후보입니다.
