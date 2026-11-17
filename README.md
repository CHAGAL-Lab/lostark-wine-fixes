# Lost Ark KR — Wine fixes for Linux

[한국어](README.md) · [English](docs/README.en.md)

우분투 Wine에서 로스트아크(STOVE 한국 클라이언트) 실행 시 생기는 문제를 해결하는 패치와 스크립트

## 문제 목록

| 문서 | 증상 | 해결 방식 |
| --- | --- | --- |
| [docs/korean-duplicate-input.md](docs/korean-duplicate-input.md) | 채팅에서 한글이 여러 번 입력됨 | Wine 패치, 레지스트리 |
| [docs/korean-skill-keys.md](docs/korean-skill-keys.md) | 한글 모드에서 스킬 키가 안 나감 | Wine 패치 |
| [docs/dlss.md](docs/dlss.md) | DLSS가 "지원 안되는 그래픽카드"로 나옴 | prefix 설정 |

원인, 되돌리기, 진단 방법은 각 문서에 있음.

## 한글 입력 패치

Wine 11.15-staging 기준. 지금 쓰는 Wine 폴더 옆에 패치된 복사본을 만들고, 런처가 그 복사본을 쓰게 바꾸는 방식이라 원본은 그대로 남음.

```bash
sudo apt install gcc-mingw-w64 flex bison autoconf libx11-dev libxext-dev libxi-dev \
    libxrandr-dev libxrender-dev libxfixes-dev libxcursor-dev libxinerama-dev \
    libxcomposite-dev libxkbregistry-dev libgl-dev libvulkan-dev

scripts/build.sh 11.15 ~/.local/share/wine-runners/wine-11.15-staging-amd64
WINEPREFIX=~/.wine-stove-staging wine reg add 'HKCU\Software\Wine\X11 Driver' /v InputStyle /d root /f
```

빌드가 끝나면 ~/.config/stove-launcher/env의 STOVE_WINE_DIR를 출력된 폴더로 바꾸고 STOVE 재시작. 수정 하나만 넣으려면 `--only duplicate-input` 또는 `--only skill-keys`.

## DLSS 설정

STOVE를 끈 상태에서 실행.

```bash
scripts/setup-dlss.sh            # 적용
scripts/setup-dlss.sh --revert   # 되돌리기
```

## 라이선스

scripts, docs는 [MIT](LICENSE). patches는 Wine 소스를 고친 것이라 Wine과 같은 LGPL-2.1-or-later.
