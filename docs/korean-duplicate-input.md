---
date: 2026-11-13
status: 해결
wine: 11.15-staging
input_method: ibus-hangul (XIM)
patches:
  - patches/0001-imm32-clear-delivered-result-string.patch
settings:
  - HKCU\Software\Wine\X11 Driver InputStyle=root
notes:
  - 조합 중인 글자가 채팅창에 안 보임 (InputStyle=root 부작용)
  - Wine 출력을 파이프로 넘기면 crashpad_handler 때문에 멈춤
---

# 한글 중복 입력

## 증상

게임 채팅에서 한글을 치면 같은 글자가 여러 번 들어감.

- "안녕"이 "안안안녕녕녕"으로 입력됨
- "아."가 "아아아."로 입력됨

같은 Wine prefix의 메모장(`wine notepad`)에서는 정상으로 입력됨. 그래서 ibus나 Wine의 한글 입력 자체가 고장 난 게 아니라, 로스트아크가 입력기 메시지를 처리하는 방식과 Wine이 메시지를 보내는 방식이 안 맞는 문제로 봄.

## 원인

한글을 칠 때 입력기는 "조합 중인 글자"와 "확정된 글자"를 따로 보냄. 이 과정에서 두 가지가 겹쳐서 같은 글자가 여러 번 들어감.

1. 확정 순서 문제: ibus는 글자를 확정할 때 "조합 끝" 신호를 확정된 글자보다 먼저 보냄. Wine은 이걸 결과가 비어 있는 조합 끝 메시지(WM_IME_ENDCOMPOSITION)로 게임에 넘기는데, 로스트아크는 이 메시지를 받을 때 지금까지 조합하던 글자를 한 번 더 넣음
2. 확정 글자가 안 지워지는 문제: Wine은 확정된 글자(GCS_RESULTSTR)를 게임에 전달한 뒤에도 그 값을 지우지 않음. 로스트아크는 다음 키를 받거나 글자 메시지(WM_CHAR)를 받을 때마다 확정 글자를 다시 읽어서 또 넣음

Windows에서는 확정과 다음 키 처리가 같은 순간에 일어나서 이런 차이가 드러나지 않음.

## 해결 방법

두 원인을 각각 막아야 해서 설정과 패치가 둘 다 필요함.

1. 레지스트리 설정: HKCU\Software\Wine\X11 Driver의 InputStyle을 root로 변경
   - Wine이 조합 중인 글자를 게임에 넘기지 않게 됨. 1번 원인이 사라짐
   - 부작용으로 조합 중인 글자가 채팅창에 안 보이고, 확정된 뒤에 나타남
2. patches/0001-imm32-clear-delivered-result-string.patch (imm32, Wine의 입력기 연결 부분)
   - 확정 글자를 게임에 전달한 뒤에는 지워서, 게임이 다시 읽어도 빈 값을 받게 함. 2번 원인이 사라짐
   - 지우는 시점은 두 군데: 일반 키가 입력기를 그냥 통과할 때, 입력기가 조합 결과를 다 전달하고 조합을 끝냈을 때

처음에는 첫 번째 시점만 고쳤는데 "이제"가 "이이제"로 들어가는 문제가 남았음. 게임이 조합 끝 메시지 직후에 다른 경로로 확정 글자를 한 번 더 읽고 있어서, 두 번째 시점도 추가해서 해결함.

## 되돌리기

레지스트리 설정은 아래 명령으로 지움.

```bash
WINEPREFIX=~/.wine-stove-staging wine reg delete 'HKCU\Software\Wine\X11 Driver' /v InputStyle /f
```

imm32 패치는 복사본 Wine 폴더에만 들어 있어서, ~/.config/stove-launcher/env의 STOVE_WINE_DIR를 원본 Wine 폴더로 바꾸면 해제됨.

## 진단

입력기 메시지 흐름을 보려면 로그를 켜고 STOVE를 직접 실행함. 런처 스크립트는 Wine 출력을 버리기 때문에 이렇게 해야 로그가 남음.

```bash
cd ~/.wine-stove-staging/drive_c/ProgramData/Smilegate/STOVE
WINEPREFIX=~/.wine-stove-staging WINEDEBUG=fixme-all,+imm,+xim wine STOVE.exe > ~/imm.log 2>&1
```

- 로그에서 xim_set_result_string(확정 글자 도착), WM_IME_ENDCOMPOSITION(조합 끝), GCS_RESULTSTR(확정 글자 조회)이 어떤 순서로 나오는지 확인
- Wine 출력은 파일로 받아야 함. 파이프로 넘기면(`| tail` 등) STOVE의 crashpad_handler가 파이프를 계속 잡고 있어서 명령이 끝나지 않음
- 로그에는 채팅으로 친 내용도 남으니 확인 후 삭제
- 게임 프로세스에 디버거(winedbg, gdb)는 붙이지 말 것. 보안 프로그램이 감지해서 게임이 꺼짐
