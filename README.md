# Onimusha 3: Demon Siege (USA) – PS2Recomp workspace

Serial **SLUS-20694**, boot ELF `SLUS_206.94` (disc version 1.01, NTSC).
SHA-256 of the ELF: `22955889d3db316fb039d0c805debc8188c384211fb4ddbfedc3e1238e7dd78a`

> PS2Recomp is experimental. No retail game is fully playable with it yet, so the
> scripts below get you as far as a first boot. After that, getting the game to run
> means implementing stubs and overrides yourself (see "After the first boot").

## What's in this folder

| Path | Contents |
|---|---|
| `game\` | Files pulled from the ISO: `SYSTEM.CNF`, `SLUS_206.94`, `IMAGE\IMAGE.AFS` (2.2 GB game data), `IMAGE\0FLIST.DIR` and `IMAGE\MODULES\*.IRX` (the IOP modules). The runtime treats this folder as `cdrom0:`. |
| `tools\PS2Recomp\` | PS2Recomp source code, main branch (commit e563698, 2026-10-22) |
| `tools\ghidra_12.2_PUBLIC\` | Ghidra 12.2 with the **ghidra-emotionengine-reloaded v2.1.39** (R5900/PS2) extension already in `Ghidra\Extensions` |
| `tools\jdk-25.0.5.1+2\` | Eclipse Temurin JDK 25. Ghidra 12.2 requires Java 25 or newer, and the scripts use it automatically. |
| `downloads\` | The original zip files. SHA-256 for Ghidra and the JDK checked against the publishers' values. |
| `0_setup.ps1` | Downloads everything in `tools\` and copies the disc into `game\` from your own ISO |
| `config\onimusha3_analyzer_fallback.toml` | A config made with `ps2_analyzer` as a test |
| `1_…5_*.bat` | The workflow, run in order |

`game\`, `tools\` and `downloads\` are **not in this repository** (see `.gitignore`).
After cloning, run once in PowerShell:

```powershell
.\0_setup.ps1 -Iso "C:\path\to\Onimusha 3 - Demon Siege (USA).iso"
```

You must supply your own legally dumped disc. Never commit game files or links to them.

## Why Ghidra is required for this game

The `file` command reports the ELF as "not stripped", but it has **no function symbols**. All of the code and data are in one
section from 0x00100000 to 0x0051E200. In a test run, `ps2_analyzer` found 5,853 "functions"
and named 233 SDK functions (sceGs*, sceDma*, sceVu0*, sceMc*, …). Its heuristic also
treated tables of data as code, so `ps2_recomp` produced about 16,000 unhandled-instruction errors
(clustered in sub_00470AA0, sub_004E87F4, sub_005123A8, …). Ghidra's analysis with the
Emotion Engine processor finds the real function boundaries.
That's the workflow PS2Recomp's own instructions recommend for retail games.

## Prerequisites you still need to install (Windows)

1. **Visual Studio 2022** (Community is fine) with the *Desktop development with C++* workload. MSVC is the compiler PS2Recomp is tested with.
2. **CMake 3.21+**, added to PATH
3. **Git for Windows**, added to PATH. CMake uses it to fetch fmt, toml11, ELFIO, rabbitizer, libdwarf, raylib, imgui and FFmpeg.

## Workflow

`config\onimusha3.toml` and `config\onimusha3_functions.csv` are already included (generated with step 1),
so you can skip straight to step 2. Re-run step 1 only if you change the Ghidra analysis.

Test results with the included config: 7,775 functions; `ps2_recomp` reports 7,617 unhandled-instruction errors,
most of them in five synthetic `entry_*` labels between 0x4EF000 and 0x51E200, where the bytes are ASCII text.
Those labels point at data, not code. The heuristic fallback config gives about 16,500 errors.

1. `1_ghidra_analyze.bat` runs Ghidra's auto-analysis without opening the Ghidra window and then runs `ExportPS2Functions.java`.
   It writes `config\onimusha3.toml` and `config\onimusha3_functions.csv`, and keeps the project
   in `ghidra_project\`. Expect it to take 15–60 minutes. Everything it prints is saved to
   `config\1_ghidra_analyze_output.txt`. Ghidra's launcher can't handle `(` `)` in paths, so the script
   temporarily maps this folder to a free drive letter (P:–Z:) with `subst` and removes it afterwards.
2. `2_build_tools.bat` builds `ps2_recomp.exe` and `ps2_analyzer.exe`.
3. `3_recompile.bat` turns the MIPS code into C++ in `output\`. The log goes to `recompile.log`. If there's no Ghidra config,
   it falls back to the analyzer config.
4. `4_build_runtime.bat` copies `output\*.cpp` into `ps2xRuntime\src\runner` and `*.h` into `ps2xRuntime\include`, then builds `ps2EntryRunner.exe`.
   Compiling the generated C++ is heavy. Expect a long build and a lot of RAM use.
5. `5_run.bat` boots `ps2EntryRunner.exe game\SLUS_206.94`.

## Patches to PS2Recomp

`patches\ps2_recompiled_stubs.h` replaces the recompiler's stubs header with a fixed one. Every declaration
in the generated header is already in `ps2_recompiled_functions.h`, and every generated file includes it, so
keeping it constant means a new stub binding recompiles a few files instead of all ~64,000.

`patches\*.patch` are fixes this game needs in PS2Recomp itself. `4_build_runtime.bat` applies them automatically.

- `0001-skip-empty-out-of-range-elf-segments.patch`: SLUS_206.94 has about 200 empty overlay placeholder segments.
  One is at 0x05000000, outside the 32 MB of RDRAM, and made the loader stop with
  "ELF segment 198 exceeds RDRAM bounds". Empty segments outside guest memory are now skipped with a warning.

## Manual bindings

Functions Ghidra couldn't name that were identified by hand (from their call patterns and the SIF
command IDs they send), bound to runtime handlers in `config\onimusha3.toml` under `stubs`.
This is Sony's libkernel SIF CMD/RPC library. The game's own copies talk to an IOP that isn't there,
so `sceCdInit` (0x0011D758) waited forever for the CD server (RPC 0x80000592) on a pink screen.

| Address | Function | Evidence |
|---|---|---|
| 0x0010DFD8 | `sceSifGetSreg` | reads the software-register table at 0x0051FC80 |
| 0x0010E020 | `sceSifInitCmd` | sets up the SIF DMA chain, sends cmds 0x80000000-0x80000002 |
| 0x0010E2A0 | `sceSifExitCmd` | removes the SIF DMA handler |
| 0x0010E308 | `sceSifAddCmdHandler` | (cid, func, data) table write |
| 0x0010E380 | `sceSifRemoveCmdHandler` | clears a table entry |
| 0x0010E508 | `sceSifSendCmd` | wraps the DMA send at 0x0010E3D0 |
| 0x0010E6D0 | `sceSifWriteBackDCache` | (addr, size) |
| 0x0010E780 | `sceSifInitRpc` | called by sceCdInit(0); registers handlers 0x80000008/9/A/C; waits for sreg 0 |
| 0x0010E920 | `sceSifExitRpc` | calls sceSifExitCmd |
| 0x0010EC60 | `sceSifGetOtherData` | sends 0x8000000C, waits on a semaphore |
| 0x0010EF18 | `sceSifBindRpc` | sends 0x80000009 |
| 0x0010F0E8 | `sceSifCallRpc` | sends 0x8000000A |
| 0x0010F2E0 | `sceSifCheckStatRpc` | (client) status check |
| 0x0010F320 | `sceSifSetRpcQueue` | (queue, thread) |
| 0x0010F3B8 | `sceSifRegisterRpc` | server registration |
| 0x0010F488 | `sceSifRemoveRpc` | (server, queue) |
| 0x0010F520 | `sceSifRemoveRpcQueue` | (queue) |
| 0x0010F5B0 | `sceSifGetNextRequest` | (queue) |
| 0x0010F608 | `sceSifExecRequest` | runs a server function, replies with 0x80000008 |
| 0x0010F7D0 | `sceSifRpcLoop` | GetNextRequest/ExecRequest/SleepThread loop |

### libcdvd (disc), libfileio, IOP heap, loadfile

The runtime has no CD/file/loadfile RPC servers on its IOP side; it implements these libraries on
the EE side instead, reading from the `game\` folder. Identified by RPC service ID and function number:

| Address | Function | Evidence |
|---|---|---|
| 0x0011CD98 | `sceCdCallback` | stores callback, returns previous |
| 0x0011CEE8 | `sceCdSearchFile` | SID 0x80000597, 300-byte request |
| 0x0011D390 | `sceCdNcmdDiskReady` | N-cmd 0xE |
| 0x0011D428 | `sceCdSync` | CheckStatRpc on the N-cmd client |
| 0x0011D4C8 | `sceCdSyncS` | CheckStatRpc on the S-cmd client |
| 0x0011D758 | `sceCdInit` | SID 0x80000592 |
| 0x0011DA38 | `sceCdDiskReady` | SID 0x8000059A |
| 0x0011DE38 | `sceCdRead` | N-cmd 1, 0x18-byte request |
| 0x0011E018 | `sceCdSeek` | N-cmd 5 |
| 0x0011E0E8 / 0x0011E180 / 0x0011E218 | `sceCdGetDiskType` / `sceCdGetError` / `sceCdBreak` | S-cmd 3 / 4 / 0x16 |
| 0x0011E2D0 | `sceCdMmode` | S-cmd via table; called with 2 (DVD) at boot |
| 0x0010FEA0 / 0x00110138 | `sceFsInit` / `sceFsReset` | binds SID 0x80000001 / clears its client |
| 0x00110170 0x001103F8 0x001107B0 0x00110A10 0x00110578 0x00110CD0 | `sceOpen` `sceClose` `sceRead` `sceWrite` `sceLseek` `sceIoctl` | fileio cmds 0 1 2 3 4 5 |
| 0x00112F28 0x00112FB0 0x001130A0 0x00113138 | `sceSifInitIopHeap` `sceSifAllocIopHeap` `sceSifFreeIopHeap` `sceSifLoadIopHeap` | SID 0x80000003, cmds 1 2 3 |
| 0x00113608 0x00113640 0x00113E78 | `sceSifLoadFileReset` `sceSifLoadModuleBuffer` `sceSifLoadModule` | SID 0x80000006; LoadModule is called for the 12 IRX paths at boot |
| 0x001141D8 0x00114330 0x00114358 0x001143A8 | `sceSifResetIop` `sceSifIsAliveIop` `sceSifSyncIop` `sceSifRebootIop` | SIF regs/DMA; RebootIop is called with IOPRP280.IMG |

Also identified, not bound: `printf` 0x0010DF48; main 0x00159020 → game init 0x0027A1C0.


## After the first boot

These steps follow PS2Recomp's recommended loop:
- Fix hard blockers first: "function not found", syscall TODOs, and missing CD/file stubs.
  The game uses CRI ADX (`CRI_ADXI.IRX`) and Capcom sound drivers (`SNDDRV.IRX`, `MOD*.IRX`). These run through ps2xIOP.
- To bind a stripped function to a runtime handler, add `handler@0xADDRESS` entries to `stubs`. Use
  `ret0@`/`ret1@` only for temporary triage.
- Put fixes that only apply to this game in a runtime game override (`PS2_REGISTER_GAME_OVERRIDE`, see
  `ps2xRuntime/include/game_overrides.h`). Key the override on ELF name `SLUS_206.94`.
- Help and discussion: the PS2Recomp wiki and Discord, linked from the project's README.
