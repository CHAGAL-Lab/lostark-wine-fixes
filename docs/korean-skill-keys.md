---
date: 2026-11-17
status: 해결
wine: 11.15-staging
input_method: ibus-hangul (XIM)
patches:
  - patches/0002-winex11-report-keys-consumed-by-xim.patch
  - patches/0003-imm32-send-consumed-keydown-directly.patch
depends_on:
  - korean-duplicate-input.md
notes:
  - 한글 모드에서 스킬 키가 최대 30ms 늦게 들어갈 수 있다
  - winex11은 staging 적용 소스로 빌드해야 한다
  - 실패한 시도 세 가지가 본문에 있다
---

# 한글 모드에서 스킬 키가 안 나가는 문제

한글 모드에서 Q, W, E, R 같은 스킬 키는 반응이 없는데 I(인벤토리), K(스킬창) 같은 UI 단축키는 열렸다. 영어 모드에서는 스킬이 정상이었다.

## 원인

키는 키보드, X 서버, ibus, Wine, 게임 순서로 전달된다. Windows에서는 IME가 운영체제 안에 있어서 게임과 직접 주고받지만, 리눅스에서는 ibus가 Wine보다 먼저 키를 받는다.

- ibus는 한글 조합에 쓴 KeyPress를 가져가고 Wine에 넘기지 않는다. 게임은 키가 눌린 것을 모르고, 조합된 글자(ㅂ, ㅑ)만 받는다.
- UI 단축키는 글자로도 열리지만, 스킬은 WM_KEYDOWN을 받아야 나간다. 그래서 I와 K는 되고 Q, W, E, R은 안 됐다. 자음과 모음의 차이가 아니다.
- Windows IME는 키를 쓰더라도 게임에 WM_KEYDOWN(VK_PROCESSKEY)을 보낸다. Wine에는 이 동작이 없다.
- 게임은 매 프레임 `ImmAssociateContextEx(hwnd, NULL, IACE_CHILDREN)`를 불러 입력기를 끄려 한다. 하지만 이 호출은 자식 창에만 적용되어 효과가 없고, Wine은 그와 상관없이 키를 ibus로 보낸다.
- ibus는 영어 모드에서도 모든 키를 먼저 가져갔다가, 쓰지 않은 키를 되돌려 보낸다(forward).
- 게임은 스킬 키를 알아낼 때 ImmGetVirtualKey를 부르지 않는다. Wine의 imm32가 ImmTranslateMessage에서 큐에 넣는 WM_KEYDOWN('Q')를 그대로 쓴다.

## 해결 (둘 다 필요)

1. patches/0002-winex11-report-keys-consumed-by-xim.patch
   - XIM이 가져간 키를 최대 30ms 보류한다.
   - ibus가 되돌려 보내면 원래 경로로 처리한다. 영어 입력이 여기에 해당한다.
   - 30ms 안에 돌아오지 않으면 한글 조합에 쓰인 키다. dwExtraInfo에 0x494d4546("IMEF")을 붙여 게임에 키를 보낸다.
   - 보류한 키는 X11DRV_ProcessEvents가 돌 때와 다른 키 이벤트가 오기 전에 내보낸다. 키 순서가 유지된다.
   - 보류 목록은 스레드별이다. 스레드마다 자기 X 연결의 이벤트를 읽기 때문이다.
2. patches/0003-imm32-send-consumed-keydown-directly.patch
   - ImmTranslateMessage가 표시가 붙은 키의 WM_KEYDOWN을 큐에 넣지 않고(PostMessage) 창에 바로 보낸다(SendMessage).
   - 큐를 거치면 게임의 TranslateMessage가 영어 글자 WM_CHAR를 만들어 한글 채팅에 섞인다. 바로 보내면 게임은 키를 받아 스킬을 쓰고, 글자는 입력기가 조합한 것만 들어간다.

한글 모드에서 스킬 키는 최대 30ms 늦게 들어갈 수 있다. 영어 모드는 ibus가 바로 되돌려 보내므로 거의 늦지 않는다.

## 실패한 시도

| 시도 | 결과 | 이유 |
| --- | --- | --- |
| 가져간 키를 바로 게임에 보내기만 함 | 스킬은 되지만 한글 채팅에 "aㅁsdㄴㅇ"처럼 영어가 섞임 | 큐에 들어간 WM_KEYDOWN이 TranslateMessage를 거쳐 WM_CHAR가 됨 |
| imm32에서 그 WM_KEYDOWN을 버림 | 스킬이 안 나가고 한글 채팅 뒤 키가 멈춤 | 게임은 그 WM_KEYDOWN으로 스킬을 판단함 |
| 보류 없이 표시를 붙여 바로 보냄 | 영어 채팅이 안 됨 | 영어 모드 키도 ibus를 거쳐서 모두 표시가 붙음 |

## 빌드할 때 주의

- winex11은 staging 패치(rawinput, scancode 등)가 건드리므로 반드시 staging을 적용한 소스로 빌드한다. scripts/build.sh가 그렇게 한다.
- configure에서 X 확장 헤더가 빠지면 그 기능이 꺼진 winex11.so가 만들어진다. 처음 빌드 때 Xcomposite와 xkbregistry가 빠졌었다. 스크립트가 원본과 라이브러리 목록을 비교해서 막는다.
- 설치하는 파일은 runner의 lib/wine/x86_64-unix/winex11.so와 lib/wine/x86_64-windows/imm32.dll이다.

## 되돌리기

STOVE를 끄고 원본 runner로 돌아간다. 11-13 수정만 남기고 싶으면 0001만 적용한 imm32.dll과 원본 winex11.so를 쓴다.

## 진단

```bash
cd ~/.wine-stove-staging/drive_c/ProgramData/Smilegate/STOVE
WINEPREFIX=~/.wine-stove-staging WINEDEBUG=fixme-all,+imm,+key wine STOVE.exe > ~/key.log 2>&1
```

로그에서 imefix로 시작하는 줄을 본다.

| 로그 | 뜻 |
| --- | --- |
| holding filtered KeyPress | ibus가 키를 가져가서 보류함 |
| forwarded back | ibus가 되돌려 보내서 원래 경로로 처리함 |
| reporting consumed keycode | 돌아오지 않아서 표시를 붙여 게임에 보냄 |
| sending consumed key | imm32가 그 키를 창에 바로 보냄 |

정상이면 한글 조합 키는 holding 다음에 reporting이, 영어 키는 holding 다음에 forwarded back이 나온다. 로그에 채팅 내용이 남으니 확인 후 지운다.
