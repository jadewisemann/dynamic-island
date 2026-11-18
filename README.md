# OmniIsland

[OmniWM](https://github.com/OmniNull/OmniWM)용 다이나믹 아일랜드 스타일 macOS 앱입니다.

- 평소에는 보이지 않습니다. 노치가 있는 화면에서는 노치와 같은 검은 모양으로 숨어 있고, 노치가 없는 화면에서는 완전히 사라집니다.
- **Option(⌥) 키를 누르고 있으면** 노치에서 아래로 바가 내려오면서 현재 모니터의 워크스페이스 목록과 포커스된 앱을 보여 줍니다.
- **워크스페이스 전환이나 창 이동이 실제로 일어나면** 바가 스프링 애니메이션으로 한 번 더 펼쳐지면서 "어디에서 어디로" 이동했는지 보여 줍니다.
- 애니메이션 종류와 속도, 색상, 크기, 트리거 키는 모두 설정 파일로 바꿀 수 있고, 파일을 저장하면 바로 반영됩니다.

OmniWM 내장 워크스페이스 바와 달리 macOS의 "동작 줄이기"나 OmniWM 애니메이션 설정과 상관없이 동작합니다.

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
| `behavior.showEventsWithoutModifier` | `true` | 키를 누르지 않았을 때 일어난 이동도 펼쳐서 보여 줍니다. |
| `behavior.eventDurationMs` | `1700` | 펼쳐진 상태가 유지되는 시간입니다. |
| `behavior.showWorkspaceSwitch` / `showWindowMove` | `true` | 이벤트 종류별로 켜고 끕니다. |
| `behavior.showEmptyWorkspaces` | `false` | 창이 없는 워크스페이스도 목록에 보여 줍니다. |
| `behavior.screen` | `"notch"` | `notch`(노치 있는 화면), `main`(메뉴 막대 화면), `active`(OmniWM이 조작 중인 모니터) 중 하나입니다. |
| `behavior.hiddenStyle` | `"auto"` | `notch`는 숨었을 때 노치 크기의 검은 모양을 남기고, `fade`는 완전히 사라집니다. `auto`는 화면에 노치가 있는지 보고 고릅니다. |
| `behavior.coalesceMs` | `140` | 이 시간 안에 겹친 이벤트를 하나로 합칩니다. |
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
| `widgets.leftWing` / `rightWing` | `"app"` / `"workspace"` | 노치 양옆에 보여 줄 내용입니다. `app`, `workspace`, `clock`, `date`, `windows`, `nextEvent`(다음 일정), `notifications`(놓친 알림 수), `none` 중 하나입니다. |
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
| `animation.style` | `"spring"` | `spring`, `bouncy`, `smooth`, `snappy`, `easeInOut`, `none` 중 하나입니다. |
| `animation.response` / `dampingFraction` | `0.45` / `0.76` | `spring`일 때 적용됩니다. 감쇠 값이 낮을수록 더 많이 튕깁니다. |
| `animation.durationMs` | `380` | `spring`이 아닌 스타일의 재생 시간입니다. |
| `animation.speed` | `1` | 모든 움직임의 속도 배율입니다. |
| `animation.contentTransition` | `"blur"` | 내용이 나타나는 방식입니다. `blur`, `fade`, `slide`, `none` 중 하나입니다. (예전의 `blurTransitions: false`는 `fade`로 읽습니다.) |
| `animation.popOnEvent` | `true` | 이벤트가 들어올 때 살짝 커졌다가 돌아오는 효과입니다. |

설정 창의 테마 탭에는 기본 테마 6가지와, r/unixporn 등에서 많이 쓰는 커뮤니티 테마(Catppuccin Mocha·Latte, Nord, Gruvbox, Tokyo Night, Rosé Pine·Dawn, Dracula, Everforest, Kanagawa)가 프리셋으로 들어 있습니다. 지금 색 구성을 "내 테마"로 저장하거나 `.json` 파일로 내보내고 가져올 수도 있습니다.

예를 들어 더 통통 튀는 느낌을 원하면 다음처럼 적습니다.

```json5
{
  "animation": { "style": "spring", "response": 0.5, "dampingFraction": 0.6 },
  "appearance": { "accentColor": "#FF9F0A", "expandedWidth": 440 },
}
```

## 알림과 일정

macOS에는 다른 앱의 알림을 읽는 공식 API가 없어서, 두 가지 경로를 함께 씁니다.

- **알림 배너 관찰**: 알림 배너를 그리는 `NotificationCenter` 프로세스를 손쉬운 사용 API로 관찰해서, 배너가 뜨는 순간 앱 이름, 제목, 본문을 읽습니다. 추가 권한이 필요 없지만, 배너가 뜨지 않는 알림은 읽을 수 없습니다.
- **알림 데이터베이스**: macOS가 알림을 기록하는 데이터베이스(`~/Library/Group Containers/group.com.apple.usernoted/db2/db`)를 1.5초마다 읽습니다. 시스템 설정 → 개인정보 보호 및 보안 → 전체 디스크 접근 권한에서 OmniIsland를 켜야 동작합니다. 형식이 공개되어 있지 않아서 macOS 업데이트 후 동작하지 않을 수 있습니다.
- 두 경로가 같은 알림을 보면 20초 안의 같은 내용은 한 번만 보여 줍니다.
- 배너 판독이 맞지 않으면 메뉴 막대 아이콘 → 알림 → "알림 배너 구조 기록 (1분)"을 누릅니다. 테스트 알림을 보내고 1분 동안 권한 상태, 데이터베이스 상태, 배너 구조를 `~/Library/Logs/OmniIsland/notification-banners.log`에 남긴 뒤 Finder로 보여 줍니다. 평소 동작 기록은 `~/Library/Logs/OmniIsland/omni-island.log`에 남습니다.

### 권한 설정 도우미

처음 실행하거나 필요한 권한이 빠져 있으면 "OmniIsland 권한 설정" 창이 열립니다. 손쉬운 사용(필수), 전체 디스크 접근(알림 데이터베이스용), 캘린더를 한 단계씩 안내하고, 각 단계에서 해당 시스템 설정 화면을 바로 엽니다. 권한이 켜지면 자동으로 다음 단계로 넘어갑니다. macOS는 전체 디스크 접근 권한을 앱이 직접 요청할 수 없으므로, 이 단계에서는 목록에서 OmniIsland를 켜거나 "Finder에서 앱 보기"로 연 앱을 목록으로 끌어다 놓아야 합니다. 건너뛴 선택 권한은 다음 실행 때 다시 묻지 않으며, 메뉴 막대 아이콘의 "권한 설정…"에서 언제든 다시 열 수 있습니다.

일정은 EventKit으로 읽습니다. 설정 창의 "알림·일정" 탭에서 캘린더를 켜면 macOS가 캘린더 접근 권한을 묻습니다. 노치 양옆 위젯을 "다음 일정"으로 바꾸면 다음 일정과 남은 시간이 보이고, 일정이 시작되기 전에는 알림 카드가 펼쳐집니다.

## 문제 해결

- **메뉴에 "OmniWM IPC에 연결할 수 없습니다"가 보입니다**: OmniWM 메뉴에서 **Enable IPC**를 켰는지 확인합니다. 켜면 앱이 알아서 다시 연결합니다.
- **"omniwmctl을 찾지 못했습니다"가 보입니다**: GUI 앱은 셸의 PATH를 물려받지 않습니다. 설정 파일의 `omniwmctlPath`에 `which omniwmctl` 결과를 적어 주세요.
- **Option 키를 눌러도 반응이 없습니다**: 손쉬운 사용 권한을 확인하고, 설정 파일의 `trigger.modifier`가 올바른지 확인합니다. 터미널에서 `build/OmniIsland.app/Contents/MacOS/OmniIsland`를 직접 실행하면 로그가 stderr로 출력됩니다.
- **OmniWM 버전이 바뀐 뒤 동작하지 않습니다**: OmniWM IPC는 클라이언트와 서버의 프로토콜 버전이 정확히 같아야 합니다. 이 앱은 `omniwmctl`을 거쳐 통신하므로, OmniWM과 같은 버전의 `omniwmctl`을 쓰고 있는지 확인합니다.

## 프로토타입의 한계

- GitHub Actions(macOS 15, Xcode 16.4)에서 컴파일은 확인했지만, 실제 OmniWM과 함께 동작하는지는 아직 확인하지 못했습니다.
- 워크스페이스 목록은 현재 활성 모니터의 워크스페이스만 보여 줍니다.
- 아일랜드는 클릭할 수 없습니다. 클릭해서 워크스페이스를 전환하는 기능은 다음 단계 후보입니다.
