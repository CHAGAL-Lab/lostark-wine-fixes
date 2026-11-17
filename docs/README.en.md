# Lost Ark KR — Wine fixes for Linux

[한국어](../README.md) · English

Patches and scripts that fix problems when running Lost Ark (Korean STOVE client) under Wine on Ubuntu.

## Problems

| Document | Symptom | Fix |
| --- | --- | --- |
| [korean-duplicate-input.md](korean-duplicate-input.md) | Korean text is entered several times in chat | Wine patch, registry |
| [korean-skill-keys.md](korean-skill-keys.md) | Skill keys do nothing in Korean input mode | Wine patch |
| [dlss.md](dlss.md) | DLSS shows "지원 안되는 그래픽카드" (unsupported graphics card) | prefix settings |

Causes, how to undo and how to diagnose are in each document (written in Korean).

## Korean input patches

Based on Wine 11.15-staging. A patched copy is built next to the Wine folder you use now, and the launcher is pointed at the copy, so the original stays untouched.

```bash
sudo apt install gcc-mingw-w64 flex bison autoconf libx11-dev libxext-dev libxi-dev \
    libxrandr-dev libxrender-dev libxfixes-dev libxcursor-dev libxinerama-dev \
    libxcomposite-dev libxkbregistry-dev libgl-dev libvulkan-dev

scripts/build.sh 11.15 ~/.local/share/wine-runners/wine-11.15-staging-amd64
WINEPREFIX=~/.wine-stove-staging wine reg add 'HKCU\Software\Wine\X11 Driver' /v InputStyle /d root /f
```

When the build finishes, set STOVE_WINE_DIR in ~/.config/stove-launcher/env to the printed folder and restart STOVE. To include only one fix, add `--only duplicate-input` or `--only skill-keys`.

## DLSS setup

Run it with STOVE closed.

```bash
scripts/setup-dlss.sh            # apply
scripts/setup-dlss.sh --revert   # undo
```

## License

scripts and docs are [MIT](../LICENSE). patches modify Wine source and follow Wine's LGPL-2.1-or-later.
