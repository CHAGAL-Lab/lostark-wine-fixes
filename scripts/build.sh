#!/bin/bash
# build.sh: apply wine-staging and this repository's patches to the Wine source, then create a copy
# of the runner with the patched files.
#
# Usage: scripts/build.sh [--only duplicate-input|skill-keys] <wine version> <source runner> [work dir]
#   e.g. scripts/build.sh 11.15 ~/.local/share/wine-runners/wine-11.15-staging-amd64
#        scripts/build.sh --only duplicate-input 11.15 ~/.local/share/wine-runners/wine-11.15-staging-amd64
#
# Fixes (both unless --only is given):
#   duplicate-input  Korean text entered several times. Patch 0001, changes imm32.dll only.
#   skill-keys       Skill keys in Korean input mode. Patches 0002 and 0003, change winex11.so and imm32.dll.
#
# Result: a copy next to the source runner, named <source>-imefix with both fixes or <source>-imefix-<fix>
# with one. The source runner is not modified. Set STOVE_WINE_DIR in ~/.config/stove-launcher/env yourself.
#
# Build dependencies:
#   sudo apt install gcc-mingw-w64 flex bison autoconf libx11-dev libxext-dev libxi-dev libxrandr-dev \
#        libxrender-dev libxfixes-dev libxcursor-dev libxinerama-dev libxcomposite-dev libxkbregistry-dev \
#        libgl-dev libvulkan-dev
# wine-<version>.tar.xz and wine-staging-<version>.tar.gz already in the work dir are used instead of downloading.
set -euo pipefail

usage() { sed -n '5,7p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 1; }

FIXES="duplicate-input skill-keys"
SUFFIX="imefix"
if [ "${1:-}" = "--only" ]; then
    case "${2:-}" in
        duplicate-input|skill-keys) FIXES="$2"; SUFFIX="imefix-$2" ;;
        *) echo "--only takes duplicate-input or skill-keys." >&2; usage ;;
    esac
    shift 2
fi
[ $# -ge 2 ] || usage

VER="$1"
SRC_RUNNER="$(readlink -f "$2")"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(readlink -f "${3:-$HOME/.cache/lostark-wine-fixes/build-$VER}")"
DST_RUNNER="${SRC_RUNNER%-amd64}-$SUFFIX"
[ "$DST_RUNNER" = "$SRC_RUNNER" ] && DST_RUNNER="$SRC_RUNNER-$SUFFIX"

patches_for() {
    case "$1" in
        duplicate-input) echo "$REPO/patches/0001-imm32-clear-delivered-result-string.patch" ;;
        skill-keys) echo "$REPO/patches/0002-winex11-report-keys-consumed-by-xim.patch"
                    echo "$REPO/patches/0003-imm32-send-consumed-keydown-directly.patch" ;;
    esac
}
has_fix() { case " $FIXES " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }

[ -x "$SRC_RUNNER/bin/wine" ] || { echo "Not a Wine runner: $SRC_RUNNER" >&2; exit 1; }
[ -e "$DST_RUNNER" ] && { echo "Already exists (remove or rename it, then retry): $DST_RUNNER" >&2; exit 1; }
"$SRC_RUNNER/bin/wine" --version 2>/dev/null | grep -q Staging \
    || echo "Warning: the source runner does not look like a staging build. The patches are built from staging source." >&2
echo "Fixes: $FIXES"

mkdir -p "$WORK" && cd "$WORK"
MAJOR="${VER%%.*}"
[ -f "wine-$VER.tar.xz" ] || curl -fL -O "https://dl.winehq.org/wine/source/$MAJOR.x/wine-$VER.tar.xz"
[ -f "wine-staging-$VER.tar.gz" ] || curl -fL -o "wine-staging-$VER.tar.gz" \
    "https://github.com/wine-staging/wine-staging/archive/refs/tags/v$VER.tar.gz"

# Source with staging only. Each fix combination patches its own copy of it.
if [ ! -d staged ]; then
    echo "Preparing source: wine $VER + staging"
    rm -rf staged.tmp staging && mkdir staged.tmp staging
    tar xf "wine-$VER.tar.xz" -C staged.tmp --strip-components=1
    tar xf "wine-staging-$VER.tar.gz" -C staging --strip-components=1
    (cd staged.tmp && python3 ../staging/staging/patchinstall.py --all --backend=patch --no-autoconf > ../patchinstall.log 2>&1)
    (cd staged.tmp && tools/make_requests && autoreconf -f) > autoconf.log 2>&1
    mv staged.tmp staged
fi

SRC="src-$SUFFIX"
if [ ! -d "$SRC" ]; then
    rm -rf "$SRC.tmp" && cp -a staged "$SRC.tmp"
    for fix in $FIXES; do
        for p in $(patches_for "$fix"); do
            echo "Applying $(basename "$p")"
            (cd "$SRC.tmp" && patch -p1 < "$p")
        done
    done
    mv "$SRC.tmp" "$SRC"
fi

BUILD="build64-$SUFFIX"
mkdir -p "$BUILD" && cd "$BUILD"
if [ ! -f Makefile ]; then
    echo "configure (log: $WORK/configure-$SUFFIX.log)"
    "../$SRC/configure" --enable-archs=x86_64 --without-freetype --without-wayland --without-gstreamer \
        --without-pulse --without-alsa --without-cups --without-sane --without-usb --without-v4l2 \
        --without-pcap --without-netapi --without-krb5 --without-gssapi --without-dbus --without-gnutls \
        > "../configure-$SUFFIX.log" 2>&1
fi

TARGETS="dlls/imm32/x86_64-windows/imm32.dll"
has_fix skill-keys && TARGETS="$TARGETS dlls/winex11.drv/winex11.so"
echo "make (log: $WORK/make-$SUFFIX.log)"
# shellcheck disable=SC2086
make -j"$(nproc)" $TARGETS > "../make-$SUFFIX.log" 2>&1

if has_fix skill-keys; then
    # If the new build lacks an X library the original winex11.so uses, that feature is silently disabled.
    libs() { strings -a "$1" | grep -E '^lib[A-Za-z0-9]+\.so\.[0-9]+$' | grep -vE '^lib(c|dl|m|pthread)\.so' | LC_ALL=C sort -u; }
    missing="$(LC_ALL=C comm -23 <(libs "$SRC_RUNNER/lib/wine/x86_64-unix/winex11.so") <(libs dlls/winex11.drv/winex11.so))"
    if [ -n "$missing" ]; then
        echo "Stopped: the new winex11.so lacks these libraries. Install their -dev packages, delete $WORK/$BUILD and run again:" >&2
        echo "$missing" >&2
        exit 1
    fi
fi

cp -a "$SRC_RUNNER" "$DST_RUNNER"
x86_64-w64-mingw32-strip -o "$DST_RUNNER/lib/wine/x86_64-windows/imm32.dll" dlls/imm32/x86_64-windows/imm32.dll
grep -q imefix "$DST_RUNNER/lib/wine/x86_64-windows/imm32.dll"
if has_fix skill-keys; then
    strip -o "$DST_RUNNER/lib/wine/x86_64-unix/winex11.so" dlls/winex11.drv/winex11.so
    grep -q imefix "$DST_RUNNER/lib/wine/x86_64-unix/winex11.so"
fi
echo "Done: $DST_RUNNER"
echo "To use it, set STOVE_WINE_DIR in ~/.config/stove-launcher/env to this path and restart STOVE."
has_fix duplicate-input && echo "The duplicate input fix also needs the registry value InputStyle=root (README, step 4)."
exit 0
