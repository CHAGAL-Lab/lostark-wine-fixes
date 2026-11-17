---
date: 2026-11-17
status: 해결
gpu: NVIDIA GeForce RTX 5070 Ti (드라이버 595.99)
dxvk: 2.4
dxvk_nvapi: 0.9.3 (Proton Hotfix에서 복사)
patches: 없음 (prefix 설정만 변경)
script: scripts/setup-dlss.sh
notes:
  - 한글 입력 문제와는 별개
  - DXVK_ENABLE_NVAPI 환경변수는 STOVE 런처를 먹통으로 만들어서 안 씀
  - 프레임이 이미 충분하면 DLSS를 켜도 체감 차이가 작음
---

# DLSS "지원 안되는 그래픽카드"

## 증상

게임 그래픽 설정에서 NVIDIA DLSS를 고르면 "지원 안되는 그래픽카드"라고 나옴.

그래픽카드가 안 잡힌 건 아님. 게임은 NVIDIA GPU로 정상 렌더링하고 있고(DXVK가 DirectX를 Vulkan으로 바꿔서 실행), DLSS를 켜는 데 필요한 부품만 빠져 있음.

## 원인

DLSS를 쓰려면 게임이 "이 카드가 NVIDIA이고 DLSS를 지원하는지" 물어보고, DLSS 본체를 불러와야 함. Steam의 Proton은 이 준비를 자동으로 해 주지만, STOVE용으로 직접 만든 Wine prefix에는 하나도 없었음.

| 빠진 것 | 역할 |
| --- | --- |
| nvapi64.dll (dxvk-nvapi) | 게임이 NVIDIA 카드 정보와 DLSS 지원 여부를 묻는 창구. Windows에서는 NVIDIA 드라이버가 설치하는 파일 |
| nvngx.dll, _nvngx.dll | DLSS 본체. NVIDIA 리눅스 드라이버 안에 Wine용으로 들어 있음 |
| NVIDIA GPU 노출 | DXVK는 nvapi가 없는 환경을 대비해서 기본으로 NVIDIA 카드를 AMD처럼 보이게 함. 이걸 풀어야 게임이 NVIDIA로 인식함 |
| NGXCore FullPath 레지스트리 | 게임 안의 DLSS 로더가 nvngx.dll을 찾는 위치. 없으면 파일이 있어도 못 찾음 |

마지막 레지스트리가 빠지면 nvapi는 정상이어도 DLSS 본체가 안 불려 와서 같은 메시지가 계속 나옴. 실제로 앞의 세 가지를 넣은 뒤에도 이 키가 없어서 한 번 더 막혔음.

## 해결 방법

Wine을 다시 빌드할 필요 없이 prefix에 파일과 설정만 넣으면 됨. STOVE를 끄고 실행.

```bash
scripts/setup-dlss.sh
```

스크립트가 하는 일:

- nvapi64.dll(system32), nvapi.dll(syswow64): Steam에 설치된 Proton에서 복사
- nvngx.dll, _nvngx.dll(system32): /usr/lib/x86_64-linux-gnu/nvidia/wine에서 복사
- Wine이 복사한 nvapi를 쓰도록 DllOverrides의 nvapi, nvapi64를 native로 설정
- HKLM\Software\NVIDIA Corporation\Global\NGXCore의 FullPath를 C:\Windows\System32로 설정
- 로스트아크 실행 파일 폴더(drive_c/ProgramData/Smilegate/Games/LOSTARK/Binaries/Win64)의 dxvk.conf에 `dxgi.hideNvidiaGpu = False`를 넣어서 게임에만 NVIDIA 카드를 그대로 보여 줌
- 바꾸기 전에 user.reg, system.reg를 prefix 안 backup-dlss-<시각> 폴더에 백업

옵션:

| 옵션 | 뜻 | 기본값 |
| --- | --- | --- |
| --prefix | Wine prefix | $WINEPREFIX, 없으면 ~/.wine-stove-staging |
| --wine | wine, wineserver가 있는 Wine 폴더 | 런처 env의 STOVE_WINE_DIR, 없으면 PATH의 wine |
| --nvapi | dxvk-nvapi 폴더 | Steam의 Proton에서 찾음 |
| --game | 로스트아크 실행 파일 폴더 | prefix 안 기본 설치 위치 |
| --revert | 넣은 것을 전부 빼기 | |

Steam이나 Proton이 없으면 [dxvk-nvapi 릴리스](https://github.com/jp7677/dxvk-nvapi/releases)를 받아서 압축을 풀고 그 폴더를 --nvapi로 지정.

## DXVK_ENABLE_NVAPI 환경변수를 안 쓰는 이유

NVIDIA 카드를 보이게 하는 방법은 환경변수(`DXVK_ENABLE_NVAPI=1`)와 dxvk.conf 두 가지가 있음. 처음에는 런처 env에 환경변수를 넣었는데 문제가 생겨서 dxvk.conf로 바꿈.

- 환경변수는 런처가 실행하는 모든 프로그램에 적용돼서 STOVE에도 걸림
- STOVE 화면을 그리는 내장 브라우저(CEF)가 NVIDIA 카드로 인식한 뒤 그리기 프로세스가 죽었고, 런처 화면이 클릭에 반응하지 않았음
- 게임 폴더의 dxvk.conf는 로스트아크 실행 파일에만 적용돼서 STOVE는 영향을 안 받음

## 확인

DLSS가 실제로 붙었는지는 로그와 프로세스로 확인할 수 있음.

- DXVK 로그(LOSTARK_dxgi.log)에 Found config file: dxvk.conf와 dxgi.hideNvidiaGpu = False가 나오면 설정이 읽힌 것
- 게임 프로세스의 /proc/<pid>/maps에 nvngx_dlss.dll과 _nvngx.dll이 보이면 DLSS 본체가 올라온 것
- 로그를 남기려면 `DXVK_NVAPI_LOG_LEVEL=info DXVK_NVAPI_LOG_PATH=<폴더> DXVK_LOG_LEVEL=info DXVK_LOG_PATH=<폴더>`를 붙여서 STOVE 실행

## 되돌리기

STOVE를 끄고 실행.

```bash
scripts/setup-dlss.sh --revert
```

- 복사한 DLL 네 개, DllOverrides 설정, NGXCore 레지스트리를 삭제
- dxvk.conf는 스크립트가 넣은 줄만 지우고, 남는 내용이 없으면 파일도 삭제
- 되돌리기 전에도 레지스트리를 같은 방식으로 백업
