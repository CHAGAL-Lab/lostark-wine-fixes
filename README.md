# Lost Ark KR — Wine fixes for Linux

[한국어](README.md) · [English](docs/README.en.md)

우분투 Wine에서 로스트아크(STOVE 한국 클라이언트) 실행 시 생기는 문제를 해결하는 패치와 스크립트

## 문제 목록

문제마다 원인, 해결 방법, 되돌리기, 진단 방법을 문서로 정리해 둠.

| 문서 | 증상 | 해결 방식 |
| --- | --- | --- |
| [docs/korean-duplicate-input.md](docs/korean-duplicate-input.md) | 채팅에서 한글이 여러 번 입력됨 | Wine 패치, 레지스트리 |
| [docs/korean-skill-keys.md](docs/korean-skill-keys.md) | 한글 모드에서 스킬 키가 안 나감 | Wine 패치 |
| [docs/dlss.md](docs/dlss.md) | DLSS가 "지원 안되는 그래픽카드"로 나옴 | prefix 설정 |

## Wine 패치 빌드

한글 입력 문제는 Wine 자체를 고쳐야 해서, 패치를 넣은 Wine을 직접 빌드함. scripts/build.sh가 소스 다운로드부터 빌드까지 처리하고, 지금 쓰는 Wine 폴더는 그대로 둔 채 옆에 패치된 복사본을 만듦.

- 패치는 Wine 11.15-staging 기준이라 다른 버전에서는 안 맞을 수 있음
- 런처가 복사본을 쓰도록 바꿔야 적용되고, 원본으로 되돌리면 바로 해제됨

1. 빌드에 필요한 패키지 설치

   ```bash
   sudo apt install gcc-mingw-w64 flex bison autoconf libx11-dev libxext-dev libxi-dev \
       libxrandr-dev libxrender-dev libxfixes-dev libxcursor-dev libxinerama-dev \
       libxcomposite-dev libxkbregistry-dev libgl-dev libvulkan-dev
   ```

2. 지금 쓰는 Wine 폴더를 넘겨서 빌드. 기본은 한글 수정 두 개를 다 넣고, --only로 하나만 고를 수 있음

   ```bash
   # 둘 다 (결과: <원본>-imefix)
   scripts/build.sh 11.15 ~/.local/share/wine-runners/wine-11.15-staging-amd64

   # 하나만 (결과: <원본>-imefix-duplicate-input 또는 <원본>-imefix-skill-keys)
   scripts/build.sh --only duplicate-input 11.15 ~/.local/share/wine-runners/wine-11.15-staging-amd64
   scripts/build.sh --only skill-keys 11.15 ~/.local/share/wine-runners/wine-11.15-staging-amd64
   ```

3. 런처가 새 폴더를 쓰도록 ~/.config/stove-launcher/env의 STOVE_WINE_DIR를 변경

   ```bash
   : "${STOVE_WINE_DIR:=$HOME/.local/share/wine-runners/wine-11.15-staging-imefix}"
   ```

4. 중복 입력 수정을 넣었다면 레지스트리 설정도 추가한 뒤 STOVE 재시작. 이 수정은 패치와 설정이 둘 다 있어야 동작함

   ```bash
   WINEPREFIX=~/.wine-stove-staging wine reg add 'HKCU\Software\Wine\X11 Driver' /v InputStyle /d root /f
   ```

## DLSS 설정

DLSS는 Wine을 고칠 필요 없이 prefix에 파일과 설정만 넣으면 됨. STOVE를 끈 상태에서 실행.

```bash
scripts/setup-dlss.sh            # 적용
scripts/setup-dlss.sh --revert   # 되돌리기
```

- prefix는 기본으로 ~/.wine-stove-staging을 씀. 다른 곳이면 --prefix로 지정
- 필요한 dxvk-nvapi는 Steam에 설치된 Proton에서 찾아 씀. 없으면 직접 받아서 --nvapi로 지정
- 실행할 때마다 레지스트리(user.reg, system.reg)를 prefix 안 backup-dlss-<시각> 폴더에 백업

## 안 될 때

- 빌드가 "lacks these libraries"로 멈춤: 원본 Wine에 있던 X 기능이 새 빌드에서 빠진 상태. 출력된 라이브러리의 -dev 패키지를 설치하고, 작업 폴더(~/.cache/lostark-wine-fixes/build-<버전>)의 build64-* 폴더를 지운 뒤 다시 실행
- 패치를 빼고 싶음: ~/.config/stove-launcher/env의 STOVE_WINE_DIR를 원본 Wine 폴더로 바꾸고 STOVE 재시작
- 문제별 되돌리기와 진단 방법은 각 문서에 있음
- 게임 프로세스에 디버거(winedbg, gdb)는 붙이지 말 것. 보안 프로그램이 감지해서 게임이 꺼짐
- 진단 로그(+imm, +key)에는 채팅으로 친 내용이 남으니 확인 후 삭제

## 업데이트 영향

패치는 복사본 Wine 폴더에만 들어 있어서, 그 폴더를 건드리지 않는 업데이트는 영향이 없음.

| 업데이트 | 패치 |
| --- | --- |
| 로스트아크, STOVE | 유지. 게임 파일은 안 건드림 |
| 우분투 시스템 | 유지. 시스템 Wine과 별개인 폴더에 있음 |
| 패치된 Wine 폴더 삭제, 덮어쓰기 | 사라짐. scripts/build.sh로 다시 만들면 됨 |
| Wine 버전 변경 | 새 버전으로 다시 빌드해야 함. 패치가 안 맞으면 손으로 수정 필요 |

## 테스트 환경

| 항목 | 값 |
| --- | --- |
| OS | Ubuntu, GNOME Wayland (Wine은 XWayland 위에서 X11 드라이버로 동작) |
| Wine | wine-11.15-staging |
| 입력기 | ibus-hangul (XIM 방식) |
| 그래픽 | NVIDIA GeForce RTX 5070 Ti, 드라이버 595.99, DXVK 2.4 |

## 라이선스

- scripts, docs: [MIT](LICENSE)
- patches: Wine 소스를 고친 것이라 Wine과 같은 LGPL-2.1-or-later
