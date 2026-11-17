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

## 빌드와 실행

```bash
git clone https://github.com/jadewisemann/dynamic-island.git
cd dynamic-island

# 1) OmniWM 없이 애니메이션만 먼저 확인하기 (가짜 워크스페이스 5개)
swift run OmniIsland --demo
#    메뉴 막대의 캡슐 아이콘 → "애니메이션 미리보기"(⌘P)를 누를 때마다
#    워크스페이스 전환과 창 이동이 번갈아 재생됩니다.

# 2) 앱 번들로 만들어 설치하고 실행하기
scripts/bundle.sh --install      # ~/Applications/OmniIsland.app
```

처음 실행하면 **손쉬운 사용(Accessibility)** 권한을 요청합니다. 시스템 설정 → 개인정보 보호 및 보안 → 손쉬운 사용에서 OmniIsland를 켜 주세요.

- 권한이 없어도 동작은 합니다. 이 경우 Option 키 상태를 초당 40회 읽는 방식으로 대신 감지하고, 권한이 허용되면 자동으로 이벤트 기반 감지로 바뀝니다.
- `bundle.sh`는 기본적으로 ad-hoc 서명을 하므로, 다시 빌드하면 macOS가 권한을 다시 물어볼 수 있습니다. 개발자 인증서가 있다면 `OMNI_ISLAND_SIGN_IDENTITY="Apple Development: ..." scripts/bundle.sh --install`처럼 서명하면 권한이 유지됩니다.
- 로그인할 때 자동으로 실행하려면 시스템 설정 → 일반 → 로그인 항목에 `~/Applications/OmniIsland.app`을 추가합니다.

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
- 아일랜드 창은 클릭을 통과시키는 투명 패널이며, 메뉴 막대보다 위 레벨에 떠서 모든 Space와 전체 화면 앱 위에 나타납니다. 키보드 포커스를 가져가지 않습니다.
- 노치 크기는 `NSScreen.safeAreaInsets`와 `auxiliaryTopLeftArea/RightArea`로 계산합니다. 노치가 없는 화면에서는 `fallbackNotchWidth`와 메뉴 막대 높이를 사용합니다.

## 설정

설정 파일은 `~/.config/omni-island/config.json`입니다. 처음 실행할 때 주석이 달린 기본 파일이 만들어지고, 메뉴 막대 아이콘 → "설정 파일 열기"로 바로 열 수 있습니다. JSON5 형식이라 `//` 주석과 끝 쉼표를 쓸 수 있으며, 적지 않은 항목은 기본값을 사용합니다.

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
| `appearance.*` | | 배경색과 불투명도, 강조색, 글자색, 모서리 반경, 글자 크기, 알약 크기, 그림자, 펼친 너비와 높이, 앱 아이콘 표시 여부입니다. 색상은 `#RRGGBB` 또는 `#RRGGBBAA`로 적습니다. |
| `animation.style` | `"spring"` | `spring`, `bouncy`, `smooth`, `snappy`, `easeInOut`, `none` 중 하나입니다. |
| `animation.response` / `dampingFraction` | `0.45` / `0.76` | `spring`일 때 적용됩니다. 감쇠 값이 낮을수록 더 많이 튕깁니다. |
| `animation.durationMs` | `380` | `spring`이 아닌 스타일의 재생 시간입니다. |
| `animation.blurTransitions` | `true` | 내용이 나타나고 사라질 때 블러를 함께 적용합니다. |
| `animation.popOnEvent` | `true` | 이벤트가 들어올 때 살짝 커졌다가 돌아오는 효과입니다. |

예를 들어 더 통통 튀는 느낌을 원하면 다음처럼 적습니다.

```json5
{
  "animation": { "style": "spring", "response": 0.5, "dampingFraction": 0.6 },
  "appearance": { "accentColor": "#FF9F0A", "expandedWidth": 440 },
}
```

## 문제 해결

- **메뉴에 "OmniWM IPC에 연결할 수 없습니다"가 보입니다**: OmniWM 메뉴에서 **Enable IPC**를 켰는지 확인합니다. 켜면 앱이 알아서 다시 연결합니다.
- **"omniwmctl을 찾지 못했습니다"가 보입니다**: GUI 앱은 셸의 PATH를 물려받지 않습니다. 설정 파일의 `omniwmctlPath`에 `which omniwmctl` 결과를 적어 주세요.
- **Option 키를 눌러도 반응이 없습니다**: 손쉬운 사용 권한을 확인하고, 설정 파일의 `trigger.modifier`가 올바른지 확인합니다. 터미널에서 `build/OmniIsland.app/Contents/MacOS/OmniIsland`를 직접 실행하면 로그가 stderr로 출력됩니다.
- **OmniWM 버전이 바뀐 뒤 동작하지 않습니다**: OmniWM IPC는 클라이언트와 서버의 프로토콜 버전이 정확히 같아야 합니다. 이 앱은 `omniwmctl`을 거쳐 통신하므로, OmniWM과 같은 버전의 `omniwmctl`을 쓰고 있는지 확인합니다.

## 프로토타입의 한계

- 이 코드는 클라우드 환경에서 macOS SDK 없이 작성했으므로 아직 실제 기기에서 검증하지 못했습니다. 빌드 오류가 나면 알려 주세요.
- 워크스페이스 목록은 현재 활성 모니터의 워크스페이스만 보여 줍니다.
- 아일랜드는 클릭할 수 없습니다. 클릭해서 워크스페이스를 전환하는 기능은 다음 단계 후보입니다.
