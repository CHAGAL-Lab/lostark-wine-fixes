# Lost Ark KR — Wine fixes for Linux

[한국어](../README.md) · English

Fixes problems that occur when running Lost Ark (Korean STOVE client) under Wine on Ubuntu.

The detailed notes in docs/ are written in Korean.

## Problems

| Document | Symptom | Fix |
| --- | --- | --- |
| [korean-duplicate-input.md](korean-duplicate-input.md) | Korean text is entered several times in chat | Wine patch, registry |
| [korean-skill-keys.md](korean-skill-keys.md) | Skill keys do nothing in Korean input mode | Wine patch |
| [dlss.md](dlss.md) | DLSS shows "지원 안되는 그래픽카드" (unsupported graphics card) | prefix settings |

## Building the Wine patches

- Target: Wine 11.15-staging. The patches may not apply to other versions.
- The original Wine folder is left alone; a patched copy is created next to it.

1. Install the build dependencies.

   ```bash
   sudo apt install gcc-mingw-w64 flex bison autoconf libx11-dev libxext-dev libxi-dev \
       libxrandr-dev libxrender-dev libxfixes-dev libxcursor-dev libxinerama-dev \
       libxcomposite-dev libxkbregistry-dev libgl-dev libvulkan-dev
   ```

2. Build.

   ```bash
   # both Korean input fixes (result: <original>-imefix)
   scripts/build.sh 11.15 ~/.local/share/wine-runners/wine-11.15-staging-amd64

   # only one (result: <original>-imefix-duplicate-input or <original>-imefix-skill-keys)
   scripts/build.sh --only duplicate-input 11.15 ~/.local/share/wine-runners/wine-11.15-staging-amd64
   scripts/build.sh --only skill-keys 11.15 ~/.local/share/wine-runners/wine-11.15-staging-amd64
   ```

3. Point STOVE_WINE_DIR in ~/.config/stove-launcher/env at the new folder.

   ```bash
   : "${STOVE_WINE_DIR:=$HOME/.local/share/wine-runners/wine-11.15-staging-imefix}"
   ```

4. If the duplicate input fix is included, add the registry value and restart STOVE.

   ```bash
   WINEPREFIX=~/.wine-stove-staging wine reg add 'HKCU\Software\Wine\X11 Driver' /v InputStyle /d root /f
   ```

## DLSS setup

No build is needed, only files and settings in the prefix. Run it with STOVE closed.

```bash
scripts/setup-dlss.sh            # apply
scripts/setup-dlss.sh --revert   # undo
```

- Default prefix: ~/.wine-stove-staging (change with --prefix)
- dxvk-nvapi is taken from Steam's Proton automatically (or give --nvapi)
- Every run backs up user.reg and system.reg to backup-dlss-<time> inside the prefix

## If it does not work

- The build stops on a missing library: install the matching -dev package, delete build64-* in the work folder (~/.cache/lostark-wine-fixes/build-<version>) and run it again.
- To go back to unpatched Wine, point STOVE_WINE_DIR at the original folder and restart STOVE.
- Do not attach a debugger (winedbg, gdb) to the game process; the anti-cheat closes the game.
- Diagnostic logs (+imm, +key) contain what you typed in chat; delete them afterwards.

## How the skill key fix works

ibus reads keys before Wine does. A key it uses for Korean composition never reaches Wine, so the game only sees the composed character, and skills, which need WM_KEYDOWN, never fire. In English mode ibus still takes every key first and forwards back the ones it does not use.

- winex11 holds a key ibus filtered for up to 30 ms. If ibus forwards it back, it is handled as usual. If not, it is reported to the game tagged with dwExtraInfo 0x494d4546.
- imm32 delivers the WM_KEYDOWN for a tagged key straight to the window (SendMessage) instead of posting it, so the game's TranslateMessage does not turn it into a Latin WM_CHAR next to the Korean text.

## License

- scripts, docs: [MIT](../LICENSE)
- patches: modify Wine source, so they follow Wine's LGPL-2.1-or-later
