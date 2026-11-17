---
date: 2026-11-17
status: 해결
gpu: NVIDIA GeForce RTX 5070 Ti (드라이버 595.99)
dxvk: 2.4
dxvk_nvapi: 0.9.3 (Proton Hotfix에서 복사)
patches: 없음 (prefix 설정만 바꿈)
backup: ~/.wine-stove-staging/backup-dlss-20261117
notes:
  - 한글 입력 문제와는 별개다
  - DXVK_ENABLE_NVAPI 환경변수는 STOVE 런처를 먹통으로 만들어 쓰지 않는다
  - DLSS를 켜도 프레임이 충분하면 체감 차이가 작다
---

# DLSS "지원 안되는 그래픽카드"

게임 그래픽 설정에서 NVIDIA DLSS를 고르면 지원하지 않는 그래픽카드라고 나왔다. 게임은 NVIDIA GPU로 DXVK 렌더링을 하고 있었다.

## 원인

Proton은 아래 설정을 자동으로 해 주지만, 직접 만든 Wine prefix에는 없었다.

| 빠진 것 | 역할 |
| --- | --- |
| nvapi64.dll (dxvk-nvapi) | 게임이 NVIDIA 카드와 DLSS 지원 여부를 묻는 창구 |
| nvngx.dll, _nvngx.dll | DLSS 본체. NVIDIA 리눅스 드라이버에 들어 있다 |
| NVIDIA GPU 노출 | DXVK는 nvapi가 없을 때를 대비해 기본으로 NVIDIA를 AMD처럼 보이게 한다 |
| NGXCore FullPath 레지스트리 | 게임의 NGX가 nvngx.dll을 찾는 경로 |

마지막 항목이 빠져 있으면 nvapi가 정상이어도 nvngx.dll이 로드되지 않고 같은 메시지가 나온다.

## 해결

```bash
P=~/.wine-stove-staging
NVAPI="$HOME/.local/share/Steam/steamapps/common/Proton Hotfix/files/lib/wine/nvapi"
cp "$NVAPI/x86_64-windows/nvapi64.dll" "$P/drive_c/windows/system32/"
cp "$NVAPI/i386-windows/nvapi.dll" "$P/drive_c/windows/syswow64/"
cp /usr/lib/x86_64-linux-gnu/nvidia/wine/nvngx.dll /usr/lib/x86_64-linux-gnu/nvidia/wine/_nvngx.dll \
   "$P/drive_c/windows/system32/"
WINEPREFIX=$P wine reg add 'HKCU\Software\Wine\DllOverrides' /v nvapi /d native /f
WINEPREFIX=$P wine reg add 'HKCU\Software\Wine\DllOverrides' /v nvapi64 /d native /f
WINEPREFIX=$P wine reg add 'HKLM\Software\NVIDIA Corporation\Global\NGXCore' /v FullPath /d 'C:\Windows\System32' /f
```

게임 실행 파일 폴더(drive_c/ProgramData/Smilegate/Games/LOSTARK/Binaries/Win64)에 dxvk.conf를 만든다.

```ini
dxgi.hideNvidiaGpu = False
```

dxvk-nvapi는 Proton Hotfix에 들어 있던 v0.9.3을 썼다.

## DXVK_ENABLE_NVAPI 환경변수를 쓰지 않는 이유

처음에는 런처 env에 `export DXVK_ENABLE_NVAPI=1`을 넣었다. 이 변수는 STOVE에도 적용되어 STOVE 내장 브라우저(CEF)의 GPU 프로세스가 죽었고, 런처 화면이 클릭에 반응하지 않았다. 게임 폴더의 dxvk.conf는 로스트아크에만 적용되어 이 문제가 없다.

## 확인

- DXVK 로그(LOSTARK_dxgi.log)에 Found config file: dxvk.conf와 dxgi.hideNvidiaGpu = False가 나온다.
- 게임 프로세스의 /proc/<pid>/maps에 nvngx_dlss.dll과 _nvngx.dll이 보인다.
- 로그를 켜려면 `DXVK_NVAPI_LOG_LEVEL=info DXVK_NVAPI_LOG_PATH=<폴더> DXVK_LOG_LEVEL=info DXVK_LOG_PATH=<폴더>`로 STOVE를 실행한다.

## 되돌리기

추가한 DLL 네 개, DllOverrides의 nvapi와 nvapi64, NGXCore 키, 게임 폴더의 dxvk.conf를 지운다. 적용 전 user.reg와 system.reg는 ~/.wine-stove-staging/backup-dlss-20261117에 백업해 두었다.
