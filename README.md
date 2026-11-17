# lostark-wine-fixes

리눅스에서 Wine으로 STOVE와 로스트아크를 실행할 때 생긴 문제와 해결 기록이다. Wine 패치, 빌드 스크립트, 원인 분석 문서를 모아 두었다.

## 환경

| 항목 | 값 |
| --- | --- |
| OS | Ubuntu, GNOME Wayland (Wine은 XWayland 위 X11 드라이버) |
| Wine | wine-11.15-staging |
| 입력기 | ibus-hangul (XIM) |
| 그래픽 | NVIDIA GeForce RTX 5070 Ti, 드라이버 595.99, DXVK 2.4 |
| prefix | ~/.wine-stove-staging |
| 런처 | stove-launcher-fix (설정 파일 ~/.config/stove-launcher/env) |

## 해결한 문제

| 날짜 | 문제 | 해결 | 문서 |
| --- | --- | --- | --- |
| 2026-11-13 | 한글이 여러 번 입력됨 ("안녕"이 "안안안녕녕녕") | imm32 패치, InputStyle=root | docs/korean-duplicate-input.md |
| 2026-11-17 | 한글 모드에서 스킬 키가 안 나감 | winex11 패치, imm32 패치 | docs/korean-skill-keys.md |
| 2026-11-17 | DLSS가 "지원 안되는 그래픽카드"로 나옴 | dxvk-nvapi, nvngx, 레지스트리 설정 | docs/dlss.md |

## 폴더 구성

| 경로 | 내용 |
| --- | --- |
| patches/0001-imm32-clear-delivered-result-string.patch | 11-13 한글 중복 입력 수정 |
| patches/0002-winex11-report-keys-consumed-by-xim.patch | 11-17 입력기가 가져간 키를 게임에 알림 |
| patches/0003-imm32-send-consumed-keydown-directly.patch | 11-17 그 키가 채팅에 영어 글자로 들어가지 않게 함 |
| scripts/build.sh | 소스를 받아 staging과 위 패치를 적용하고, 패치된 runner 복사본을 만든다 |
| docs/ | 문제별 원인, 해결, 되돌리기, 진단 방법 |

## 빌드와 설치

패치는 Wine 11.15-staging 기준이다. 다른 버전에서는 패치가 어긋날 수 있다.

1. 빌드에 필요한 패키지를 설치한다.

   ```bash
   sudo apt install gcc-mingw-w64 flex bison autoconf libx11-dev libxext-dev libxi-dev \
       libxrandr-dev libxrender-dev libxfixes-dev libxcursor-dev libxinerama-dev \
       libxcomposite-dev libxkbregistry-dev libgl-dev libvulkan-dev
   ```

2. 원본 runner를 넘겨 빌드한다. 원본 폴더 옆에 이름이 -imefix로 끝나는 복사본이 생긴다.

   ```bash
   scripts/build.sh 11.15 ~/.local/share/wine-runners/wine-11.15-staging-amd64
   ```

3. ~/.config/stove-launcher/env의 STOVE_WINE_DIR를 새 폴더로 바꾸고 STOVE를 다시 켠다.

   ```bash
   : "${STOVE_WINE_DIR:=$HOME/.local/share/wine-runners/wine-11.15-staging-imefix}"
   ```

4. 11-13 수정은 레지스트리 설정도 함께 필요하다.

   ```bash
   WINEPREFIX=~/.wine-stove-staging wine reg add 'HKCU\Software\Wine\X11 Driver' /v InputStyle /d root /f
   ```

빌드 스크립트는 원본 runner의 winex11.so가 쓰는 X 라이브러리가 새 빌드에서 빠졌는지 확인하고, 빠졌으면 멈춘다. 이때는 빠진 라이브러리의 -dev 패키지를 설치하고 작업 폴더의 build64를 지운 뒤 다시 실행한다.

## 업데이트 영향

| 업데이트 | 패치 |
| --- | --- |
| 로스트아크, STOVE 업데이트 | 유지된다. 게임 파일은 건드리지 않는다. |
| 우분투 시스템 업데이트 | 유지된다. 패치는 별도 runner 폴더에 있다. |
| runner 폴더를 지우거나 덮어쓰기 | 사라진다. scripts/build.sh로 다시 만든다. |
| Wine 버전 변경 | 새 버전에 맞춰 다시 빌드해야 한다. 패치가 어긋나면 손으로 고친다. |

## 되돌리기

원본 runner로 돌아가려면 env의 STOVE_WINE_DIR를 원본 폴더로 바꾸고 STOVE를 다시 켠다. 문제별로 되돌리는 방법은 각 문서에 있다.

## 주의

- 게임 프로세스에 디버거(winedbg, gdb)를 붙이지 않는다. 보안 프로그램 때문에 게임이 꺼진다.
- 진단 로그(+imm, +key)에는 채팅 내용이 남는다. 확인이 끝나면 지운다.
