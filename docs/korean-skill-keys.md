---
date: 2026-11-17
status: 해결
wine: 11.15-staging
input_method: ibus-hangul (XIM)
patches:
  - patches/0002-winex11-report-keys-consumed-by-xim.patch
  - patches/0003-imm32-send-consumed-keydown-directly.patch
notes:
  - 한글 모드에서 스킬 키가 최대 30ms 늦게 들어갈 수 있음
  - winex11은 staging 적용 소스로 빌드해야 함
  - 실패한 시도 세 가지가 본문에 있음
  - 게임에서 확인한 조합은 중복 입력 수정과 함께 넣은 전체 빌드뿐
---

# 한글 모드에서 스킬 키가 안 나가는 문제

## 증상

한글 입력 모드에서 스킬만 안 나가고, 다른 단축키는 정상으로 동작함.

- Q, W, E, R 같은 스킬 키를 눌러도 반응 없음
- 같은 한글 모드에서 인벤토리(I), 스킬창(K) 같은 UI 단축키는 열림
- 영어 모드로 바꾸면 스킬도 정상

## 원인

리눅스에서는 한글 입력기(ibus)가 Wine보다 먼저 키보드 입력을 받음. Windows처럼 게임과 입력기가 직접 주고받는 구조가 아님.

한글 모드에서 Q를 누르면 ibus가 이 키를 "ㅂ" 조합에 쓰고 Wine에는 넘기지 않음. 그래서 게임은 Q가 눌렸다는 신호(WM_KEYDOWN)를 못 받고, 조합된 글자 "ㅂ"만 받음.

- UI 단축키는 글자로도 열려서 한글 모드에서도 됨
- 스킬은 키 눌림 신호가 있어야 나가서 안 됨. 자음, 모음 차이가 아니라 UI 단축키냐 스킬이냐의 차이
- Windows의 한글 입력기는 키를 조합에 쓰더라도 게임에 키 눌림 신호(VK_PROCESSKEY)를 같이 보내 줌. Wine에는 이 동작이 없음

게임도 이 문제를 피하려고 매 프레임 입력기를 끄는 함수(`ImmAssociateContextEx(hwnd, NULL, IACE_CHILDREN)`)를 부름. 하지만 이 호출은 자식 창에만 적용돼서 게임 창에는 효과가 없고, Wine은 입력기 상태와 상관없이 키를 ibus로 보냄.

고칠 때 알아야 했던 동작 두 가지:

- ibus는 영어 모드에서도 모든 키를 먼저 가져갔다가, 쓰지 않은 키만 Wine에 되돌려 보냄. 그래서 "ibus가 가져간 키"라는 것만으로는 한글 조합 키인지 알 수 없음
- 게임은 스킬 키를 알아낼 때 입력기에 원래 키를 묻지(ImmGetVirtualKey) 않음. Wine이 입력기를 거친 뒤 다시 보내 주는 키 메시지(WM_KEYDOWN 'Q')를 그대로 씀

## 해결 방법

Wine의 두 부분을 고쳐서, 한글 조합에 쓰인 키도 게임에 키 눌림으로 전달되게 함. 패치 두 개가 다 있어야 동작함.

1. patches/0002-winex11-report-keys-consumed-by-xim.patch (winex11, Wine의 X11 화면·입력 드라이버)
   - ibus가 키를 가져가면 바로 버리지 않고 최대 30ms 동안 기다림
   - 그 사이 ibus가 키를 되돌려 보내면 영어 입력이라는 뜻이라 원래대로 처리
   - 끝까지 안 돌아오면 한글 조합에 쓰인 키로 보고, 표시(dwExtraInfo = 0x494d4546, "IMEF")를 붙여서 게임에 키 눌림으로 보냄
   - 기다리던 키는 다른 키가 들어오기 전에 먼저 내보내서 키 순서가 뒤섞이지 않음
2. patches/0003-imm32-send-consumed-keydown-directly.patch (imm32, Wine의 입력기 연결 부분)
   - 표시가 붙은 키는 메시지 큐에 넣지 않고 게임 창에 바로 전달
   - 큐에 넣으면 게임이 그 키를 글자로 바꿔서(TranslateMessage, WM_CHAR) 한글 채팅에 영어 글자가 섞임
   - 바로 전달하면 게임은 키 눌림만 받아 스킬을 쓰고, 채팅에는 ibus가 조합한 한글만 들어감

부작용으로 한글 모드의 스킬 키는 최대 30ms 늦게 들어갈 수 있음. 영어 모드는 ibus가 키를 바로 되돌려 보내서 거의 안 늦음.

## 실패한 시도

지금 방식에 이르기 전에 시도했다가 문제가 생긴 방법들. 다시 손볼 때 같은 길로 가지 않도록 남겨 둠.

| 시도 | 결과 | 이유 |
| --- | --- | --- |
| ibus가 가져간 키를 바로 게임에 보내기만 함 | 스킬은 되지만 한글 채팅에 "aㅁsdㄴㅇ"처럼 영어가 섞임 | 다시 보낸 키 메시지가 큐를 거치면서 영어 글자(WM_CHAR)로 바뀜 |
| imm32에서 그 키 메시지를 아예 버림 | 스킬이 다시 안 나가고, 한글 채팅 뒤 키가 멈춤 | 게임은 바로 그 키 메시지로 스킬을 판단함 |
| 기다리지 않고 표시를 붙여 바로 보냄 | 영어 채팅이 안 됨 | 영어 모드 키도 ibus를 거치기 때문에 전부 한글 조합 키로 취급됨 |

## 빌드할 때 주의

- staging 소스로 빌드해야 함: 지금 쓰는 Wine은 staging 빌드이고, staging은 winex11의 키보드 처리(rawinput, scancode)를 이미 고쳐 둔 상태. 일반 Wine 소스로 winex11을 빌드하면 그 변경이 빠진 파일로 바뀌어서 다른 문제가 생길 수 있음. scripts/build.sh는 staging을 먼저 적용한 소스에 이 패치를 넣음
- X 확장 헤더 확인: 빌드할 때 X 확장(Xcomposite 등)의 개발 헤더가 없으면, 그 기능이 꺼진 winex11.so가 오류 없이 만들어짐. 처음 빌드 때 실제로 Xcomposite, xkbregistry가 빠졌음. scripts/build.sh는 새 파일과 원본이 쓰는 라이브러리 목록을 비교해서, 빠진 게 있으면 설치 전에 멈춤
- 바뀌는 파일: Wine 폴더의 lib/wine/x86_64-unix/winex11.so, lib/wine/x86_64-windows/imm32.dll 두 개

## 되돌리기

패치는 복사본 Wine 폴더에만 들어 있어서, 런처가 원본 Wine 폴더를 쓰게 바꾸면 해제됨.

- STOVE 종료 후 ~/.config/stove-launcher/env의 STOVE_WINE_DIR를 원본 Wine 폴더로 변경
- 중복 입력 수정은 유지하고 이 수정만 빼려면 `scripts/build.sh --only duplicate-input`으로 만든 폴더를 STOVE_WINE_DIR로 지정

## 진단

키가 어떻게 처리되는지 보려면 입력기와 키 로그를 켜고 STOVE를 직접 실행함. 런처 스크립트는 Wine 출력을 버리기 때문에 이렇게 해야 로그가 남음.

```bash
cd ~/.wine-stove-staging/drive_c/ProgramData/Smilegate/STOVE
WINEPREFIX=~/.wine-stove-staging WINEDEBUG=fixme-all,+imm,+key wine STOVE.exe > ~/key.log 2>&1
```

로그에서 imefix로 시작하는 줄이 이 패치가 남기는 기록.

| 로그 | 뜻 |
| --- | --- |
| holding filtered KeyPress | ibus가 키를 가져가서 기다리는 중 |
| forwarded back | ibus가 키를 되돌려 보내서 원래대로 처리함 (영어 입력) |
| reporting consumed keycode | 키가 안 돌아와서 표시를 붙여 게임에 보냄 (한글 조합 키) |
| sending consumed key | imm32가 그 키를 게임 창에 바로 전달함 |

- 정상이면 한글 조합 키는 holding 다음에 reporting, 영어 키는 holding 다음에 forwarded back이 나옴
- 로그에는 채팅으로 친 내용도 남으니 확인 후 삭제
