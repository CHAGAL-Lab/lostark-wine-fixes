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
  - 조합 중인 글자가 채팅창에 보이지 않는다 (InputStyle=root의 부작용)
  - Wine 출력을 파이프로 넘기면 crashpad_handler 때문에 멈춘다
---

# 한글 중복 입력

게임 채팅에서 "안녕"이 "안안안녕녕녕"으로, "아."가 "아아아."로 들어갔다.

## 원인

1. ibus는 글자를 확정할 때 조합 끝 신호를 확정 글자보다 먼저 보낸다. Wine은 이것을 결과 없는 WM_IME_ENDCOMPOSITION으로 넘기고, 로스트아크는 그때 한 번 더 넣는다.
2. Wine은 확정 글자(GCS_RESULTSTR)를 전달한 뒤에도 지우지 않는다. 로스트아크는 다음 키나 WM_CHAR를 받을 때 결과 문자열을 다시 조회해서 같은 글자를 또 넣는다.

Windows에서는 확정과 다음 키가 같은 순간에 처리되어 이 차이가 드러나지 않는다.

같은 prefix의 메모장(`wine notepad`)에서는 정상으로 입력된다. 그래서 ibus나 Wine의 입력 경로 자체가 아니라, 게임이 IME 메시지를 처리하는 방식과 Wine의 차이가 원인이라고 판단했다.

## 해결 (둘 다 필요)

1. 레지스트리 HKCU\Software\Wine\X11 Driver의 InputStyle을 root로 설정한다. 조합 중인 글자를 Wine에 넘기지 않아 1번 원인이 사라진다. 대신 조합 중인 글자가 채팅창에 보이지 않는다.
2. patches/0001-imm32-clear-delivered-result-string.patch로 2번 원인을 없앤다.
   - 일반 키가 IME를 그냥 통과할 때 남아 있는 결과 문자열을 지운다.
   - ime_set_comp_string에서 메시지 전달이 끝나고 조합도 끝났으면 결과 문자열을 지운다.

첫 번째 변경만 넣었을 때는 "이이제"처럼 한 글자가 남았다. 게임이 WM_IME_ENDCOMPOSITION 직후 다른 WM_CHAR 경로로 결과 문자열을 다시 읽었기 때문이고, 두 번째 변경으로 해결했다.

## 되돌리기

```bash
WINEPREFIX=~/.wine-stove-staging wine reg delete 'HKCU\Software\Wine\X11 Driver' /v InputStyle /f
```

imm32는 원본 runner로 돌아가면 함께 되돌아간다.

## 진단

```bash
cd ~/.wine-stove-staging/drive_c/ProgramData/Smilegate/STOVE
WINEPREFIX=~/.wine-stove-staging WINEDEBUG=fixme-all,+imm,+xim wine STOVE.exe > ~/imm.log 2>&1
```

런처 스크립트는 Wine 출력을 버리므로 STOVE.exe를 직접 실행한다. 로그에서 xim_set_result_string, WM_IME_ENDCOMPOSITION, GCS_RESULTSTR이 나오는 순서를 본다.

Wine 출력을 파이프로 넘기면(`| tail` 등) 멈춘다. crashpad_handler가 파이프를 물고 있기 때문이므로 파일로 받는다.
