#!/bin/bash
# build.sh: Wine 소스에 staging과 이 저장소의 패치를 적용하고, 패치된 imm32.dll과 winex11.so를 넣은 runner 복사본을 만든다.
#
# 사용법: scripts/build.sh <wine 버전> <원본 runner 폴더> [작업 폴더]
#   예: scripts/build.sh 11.15 ~/.local/share/wine-runners/wine-11.15-staging-amd64
#
# 결과: <원본 runner 폴더>-imefix 폴더(원본 복사본)에 패치된 파일 두 개가 들어간다. 원본 폴더는 건드리지 않는다.
# 런처 설정(~/.config/stove-launcher/env)의 STOVE_WINE_DIR는 직접 바꾼다.
#
# 필요한 패키지:
#   sudo apt install gcc-mingw-w64 flex bison autoconf libx11-dev libxext-dev libxi-dev libxrandr-dev \
#        libxrender-dev libxfixes-dev libxcursor-dev libxinerama-dev libxcomposite-dev libxkbregistry-dev \
#        libgl-dev libvulkan-dev
# 작업 폴더에 wine-<버전>.tar.xz, wine-staging-<버전>.tar.gz가 있으면 내려받지 않고 쓴다.
set -euo pipefail

VER="${1:?wine 버전을 주세요 (예: 11.15)}"
SRC_RUNNER="$(readlink -f "${2:?원본 runner 폴더를 주세요}")"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(readlink -f "${3:-$HOME/.cache/lostark-wine-fixes/build-$VER}")"
DST_RUNNER="${SRC_RUNNER%-amd64}-imefix"
[ "$DST_RUNNER" = "$SRC_RUNNER" ] && DST_RUNNER="$SRC_RUNNER-imefix"

[ -x "$SRC_RUNNER/bin/wine" ] || { echo "runner가 아닙니다: $SRC_RUNNER" >&2; exit 1; }
[ -e "$DST_RUNNER" ] && { echo "이미 있습니다(지우거나 이름을 바꾸고 다시): $DST_RUNNER" >&2; exit 1; }
"$SRC_RUNNER/bin/wine" --version 2>/dev/null | grep -q Staging \
    || echo "주의: 원본 runner가 staging 빌드가 아닌 것 같습니다. winex11.so는 staging 소스로 빌드됩니다." >&2

mkdir -p "$WORK" && cd "$WORK"
MAJOR="${VER%%.*}"
[ -f "wine-$VER.tar.xz" ] || curl -fL -O "https://dl.winehq.org/wine/source/$MAJOR.x/wine-$VER.tar.xz"
[ -f "wine-staging-$VER.tar.gz" ] || curl -fL -o "wine-staging-$VER.tar.gz" \
    "https://github.com/wine-staging/wine-staging/archive/refs/tags/v$VER.tar.gz"

if [ ! -d src ]; then
    echo "소스 준비: wine $VER + staging"
    rm -rf src.tmp staging && mkdir src.tmp staging
    tar xf "wine-$VER.tar.xz" -C src.tmp --strip-components=1
    tar xf "wine-staging-$VER.tar.gz" -C staging --strip-components=1
    (cd src.tmp && python3 ../staging/staging/patchinstall.py --all --backend=patch --no-autoconf > ../patchinstall.log 2>&1)
    (cd src.tmp && tools/make_requests && autoreconf -f) > autoconf.log 2>&1
    for p in "$REPO"/patches/*.patch; do
        echo "패치 적용: $(basename "$p")"
        (cd src.tmp && patch -p1 < "$p")
    done
    mv src.tmp src
fi

mkdir -p build64 && cd build64
if [ ! -f Makefile ]; then
    echo "configure (로그: $WORK/configure.log)"
    ../src/configure --enable-archs=x86_64 --without-freetype --without-wayland --without-gstreamer \
        --without-pulse --without-alsa --without-cups --without-sane --without-usb --without-v4l2 \
        --without-pcap --without-netapi --without-krb5 --without-gssapi --without-dbus --without-gnutls \
        > ../configure.log 2>&1
fi
echo "빌드 (로그: $WORK/make.log)"
make -j"$(nproc)" dlls/imm32/x86_64-windows/imm32.dll dlls/winex11.drv/winex11.so > ../make.log 2>&1

# 원본 runner의 winex11.so가 쓰는 X 라이브러리가 새 빌드에서 빠지면 그 기능이 꺼진 채 동작한다.
libs() { strings -a "$1" | grep -E '^lib[A-Za-z0-9]+\.so\.[0-9]+$' | grep -vE '^lib(c|dl|m|pthread)\.so' | LC_ALL=C sort -u; }
missing="$(LC_ALL=C comm -23 <(libs "$SRC_RUNNER/lib/wine/x86_64-unix/winex11.so") <(libs dlls/winex11.drv/winex11.so))"
if [ -n "$missing" ]; then
    echo "중단: 새 winex11.so에 빠진 라이브러리가 있습니다. 해당 -dev 패키지를 설치하고 build64를 지운 뒤 다시 실행하세요:" >&2
    echo "$missing" >&2
    exit 1
fi

cp -a "$SRC_RUNNER" "$DST_RUNNER"
x86_64-w64-mingw32-strip -o "$DST_RUNNER/lib/wine/x86_64-windows/imm32.dll" dlls/imm32/x86_64-windows/imm32.dll
strip -o "$DST_RUNNER/lib/wine/x86_64-unix/winex11.so" dlls/winex11.drv/winex11.so
grep -q imefix "$DST_RUNNER/lib/wine/x86_64-windows/imm32.dll"
grep -q imefix "$DST_RUNNER/lib/wine/x86_64-unix/winex11.so"
echo "완료: $DST_RUNNER"
echo "런처에 적용: ~/.config/stove-launcher/env 의 STOVE_WINE_DIR 를 위 경로로 바꾸고 STOVE를 다시 켭니다."
