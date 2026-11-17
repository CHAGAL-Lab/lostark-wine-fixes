#!/bin/bash
# setup-dlss.sh: add (default) or remove (--revert) the files and settings DLSS needs in the STOVE Wine prefix.
#
# Usage: scripts/setup-dlss.sh [--revert] [--prefix <dir>] [--wine <runner dir>] [--nvapi <dir>] [--game <dir>]
#   --prefix  Wine prefix. Default: $WINEPREFIX, else ~/.wine-stove-staging
#   --wine    runner dir with bin/wine and bin/wineserver. Default: STOVE_WINE_DIR from ~/.config/stove-launcher/env, else PATH
#   --nvapi   dxvk-nvapi dir (the one holding x86_64-windows/nvapi64.dll). Default: found in Steam's Proton
#   --game    Lost Ark executable dir. Default: <prefix>/drive_c/ProgramData/Smilegate/Games/LOSTARK/Binaries/Win64
#
# What it does: copies nvapi64.dll, nvapi.dll, nvngx.dll and _nvngx.dll, sets DllOverrides nvapi/nvapi64=native,
# sets the NGXCore FullPath registry value, and adds dxgi.hideNvidiaGpu = False to dxvk.conf in the game dir.
# user.reg and system.reg are backed up to <prefix>/backup-dlss-<time> first. STOVE must not be running.
set -euo pipefail

usage() { sed -n '4,8p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 1; }

REVERT=0 PREFIX="" WINE_DIR="" NVAPI_DIR="" GAME_DIR=""
while [ $# -gt 0 ]; do
    case "$1" in
        --revert) REVERT=1; shift ;;
        --prefix) PREFIX="${2:?}"; shift 2 ;;
        --wine) WINE_DIR="${2:?}"; shift 2 ;;
        --nvapi) NVAPI_DIR="${2:?}"; shift 2 ;;
        --game) GAME_DIR="${2:?}"; shift 2 ;;
        *) usage ;;
    esac
done

PREFIX="$(readlink -f "${PREFIX:-${WINEPREFIX:-$HOME/.wine-stove-staging}}")"
[ -f "$PREFIX/system.reg" ] || { echo "Not a Wine prefix: $PREFIX" >&2; exit 1; }
SYS32="$PREFIX/drive_c/windows/system32"
WOW64="$PREFIX/drive_c/windows/syswow64"
GAME_DIR="${GAME_DIR:-$PREFIX/drive_c/ProgramData/Smilegate/Games/LOSTARK/Binaries/Win64}"
NGX_SRC=/usr/lib/x86_64-linux-gnu/nvidia/wine
CONF_LINE="dxgi.hideNvidiaGpu = False"

if [ -z "$WINE_DIR" ] && [ -f "$HOME/.config/stove-launcher/env" ]; then
    WINE_DIR="$(set +u; source "$HOME/.config/stove-launcher/env" >/dev/null 2>&1; echo "${STOVE_WINE_DIR:-}")"
fi
if [ -n "$WINE_DIR" ]; then
    WINE="$WINE_DIR/bin/wine" WINESERVER="$WINE_DIR/bin/wineserver"
else
    WINE="$(command -v wine)" WINESERVER="$(command -v wineserver)"
fi
[ -x "$WINE" ] || { echo "wine not found. Pass the runner dir with --wine." >&2; exit 1; }
export WINEPREFIX="$PREFIX" WINESERVER WINEDEBUG=-all

# Stop if STOVE or the game runs in this prefix (processes in other prefixes do not matter).
for pid in $(pgrep -f 'STOVE\.exe|lostark\.exe' 2>/dev/null); do
    if tr '\0' '\n' < "/proc/$pid/environ" 2>/dev/null | grep -qxF "WINEPREFIX=$PREFIX"; then
        echo "STOVE or Lost Ark is running in this prefix. Close it and run again." >&2
        exit 1
    fi
done

# Never pipe wine output: background processes keep the pipe open and the command hangs.
reg() { "$WINE" reg "$@" >/dev/null 2>&1 </dev/null; }

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="$PREFIX/backup-dlss-$STAMP"
mkdir -p "$BACKUP"
cp -a "$PREFIX/user.reg" "$PREFIX/system.reg" "$BACKUP/"
echo "Registry backup: $BACKUP"

if [ "$REVERT" = 1 ]; then
    rm -f "$SYS32/nvapi64.dll" "$WOW64/nvapi.dll" "$SYS32/nvngx.dll" "$SYS32/_nvngx.dll"
    reg delete 'HKCU\Software\Wine\DllOverrides' /v nvapi /f || true
    reg delete 'HKCU\Software\Wine\DllOverrides' /v nvapi64 /f || true
    reg delete 'HKLM\Software\NVIDIA Corporation\Global\NGXCore' /f || true
    if [ -f "$GAME_DIR/dxvk.conf" ]; then
        # Remove only the lines this script added, and the file if nothing else is left.
        sed -i '/^dxgi\.hideNvidiaGpu = False$/d; /^# DLSS: /d' "$GAME_DIR/dxvk.conf"
        grep -q '[^[:space:]]' "$GAME_DIR/dxvk.conf" || rm -f "$GAME_DIR/dxvk.conf"
    fi
    "$WINESERVER" -k 2>/dev/null || true
    echo "DLSS settings removed."
    exit 0
fi

# Find dxvk-nvapi: --nvapi, else one of the Steam Proton builds
if [ -z "$NVAPI_DIR" ]; then
    for d in "$HOME/.local/share/Steam/steamapps/common/Proton Hotfix" \
             "$HOME/.local/share/Steam/steamapps/common/Proton - Experimental" \
             "$HOME"/.local/share/Steam/steamapps/common/Proton*; do
        if [ -f "$d/files/lib/wine/nvapi/x86_64-windows/nvapi64.dll" ]; then
            NVAPI_DIR="$d/files/lib/wine/nvapi"
            break
        fi
    done
fi
[ -n "$NVAPI_DIR" ] && [ -f "$NVAPI_DIR/x86_64-windows/nvapi64.dll" ] || {
    echo "dxvk-nvapi not found. Install Proton from Steam, or extract https://github.com/jp7677/dxvk-nvapi/releases and pass it with --nvapi." >&2
    exit 1
}
for f in nvngx.dll _nvngx.dll; do
    [ -f "$NGX_SRC/$f" ] || { echo "$NGX_SRC/$f is missing. Check the NVIDIA driver installation." >&2; exit 1; }
done

echo "dxvk-nvapi: $NVAPI_DIR ($(cat "$NVAPI_DIR/version" 2>/dev/null || echo unknown version))"
install -m 0644 "$NVAPI_DIR/x86_64-windows/nvapi64.dll" "$SYS32/"
[ -f "$NVAPI_DIR/i386-windows/nvapi.dll" ] && [ -d "$WOW64" ] && install -m 0644 "$NVAPI_DIR/i386-windows/nvapi.dll" "$WOW64/"
install -m 0644 "$NGX_SRC/nvngx.dll" "$NGX_SRC/_nvngx.dll" "$SYS32/"

reg add 'HKCU\Software\Wine\DllOverrides' /v nvapi /d native /f
reg add 'HKCU\Software\Wine\DllOverrides' /v nvapi64 /d native /f
reg add 'HKLM\Software\NVIDIA Corporation\Global\NGXCore' /v FullPath /d 'C:\Windows\System32' /f
"$WINESERVER" -k 2>/dev/null || true
grep -q 'NGXCore' "$PREFIX/system.reg" || { echo "The NGXCore registry value was not saved." >&2; exit 1; }

if [ -d "$GAME_DIR" ]; then
    if [ -f "$GAME_DIR/dxvk.conf" ]; then
        grep -qxF "$CONF_LINE" "$GAME_DIR/dxvk.conf" || printf '%s\n' "$CONF_LINE" >> "$GAME_DIR/dxvk.conf"
    else
        printf '# DLSS: expose the NVIDIA GPU to Lost Ark only\n%s\n' "$CONF_LINE" > "$GAME_DIR/dxvk.conf"
    fi
    echo "dxvk.conf: $GAME_DIR/dxvk.conf"
else
    echo "Warning: game dir not found, dxvk.conf not written: $GAME_DIR (set it with --game)" >&2
fi
echo "Done. Restart Lost Ark and choose DLSS in the graphics settings."
