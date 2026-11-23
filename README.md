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
   `config\1_ghidra_analyze_output.txt`. Ghidra's own launcher (`analyzeHeadless.bat`) can't handle `(` `)`
   in paths, so `ghidra_headless.ps1` starts Ghidra's Java entry point directly instead.
2. `2_build_tools.bat` applies the patches below to PS2Recomp (`apply_patches.ps1`; each patch once, recorded in
   `tools\PS2Recomp\.onimusha3-applied-patches.txt`) and builds `ps2_recomp.exe` and `ps2_analyzer.exe`.
   Re-run it (then 3, 3b and 4) whenever a patch that changes the recompiler is added.
3. `3_recompile.bat` turns the MIPS code into C++ in `output\`. The log goes to `recompile.log`. If there's no Ghidra config,
   it falls back to the analyzer config.
3b. `3b_recompile_overlays.bat` recompiles the game's code overlays (see "Code overlays" below): it extracts the
   188 code modules from `game\IMAGE\IMAGE.AFS`, runs Ghidra on them (a few minutes), recompiles each one
   with `ps2_recomp`, and writes the C++ to `output_overlays\`. Output is saved to
   `build\3b_recompile_overlays_output.txt`.
4. `4_build_runtime.bat` copies `output\*.cpp` into `ps2xRuntime\src\runner`, `output_overlays\*.cpp` into
   `ps2xRuntime\src\runner_overlays` and `*.h` into `ps2xRuntime\include`, then builds `ps2EntryRunner.exe`.
   Compiling the generated C++ is heavy. Expect a long build and a lot of RAM use.
   Per-function trace logging (`ps2_log.txt`) is off; `4_build_runtime.bat trace` turns it on (very slow game).
5. `5_run.bat` boots `ps2EntryRunner.exe game\SLUS_206.94`. Everything it prints is saved to `run_log.txt`.

## Patches to PS2Recomp

`patches\ps2_recompiled_stubs.h` replaces the recompiler's stubs header with a fixed one. Every declaration
in the generated header is already in `ps2_recompiled_functions.h`, and every generated file includes it, so
keeping it constant means a new stub binding recompiles a few files instead of all ~64,000.

`patches\*.patch` are fixes this game needs in PS2Recomp itself. `4_build_runtime.bat` applies them automatically.

- `0001-skip-empty-out-of-range-elf-segments.patch`: SLUS_206.94 has about 200 empty overlay placeholder segments.
  One is at 0x05000000, outside the 32 MB of RDRAM, and made the loader stop with
  "ELF segment 198 exceeds RDRAM bounds". Empty segments outside guest memory are now skipped with a warning.
- `0002-iop-sif-initialised-at-boot.patch`: on real hardware the IOP BIOS has initialised SIF before game modules
  load, so `sceSifCheckInit()` returns 1. The emulator started at 0, and SNDDRV printed "yet sif hasn't been init".
- `0003-iop-module-start-argc-argv.patch`: IRX entry points are `start(argc, argv)` with `argv[0]` = module path.
  The emulator passed `(argumentSize, rawBuffer)`. Capcom's SNDDRV needs `argc == 11` (path + 10 settings) and
  otherwise exits without becoming resident, so the game waited forever for its RPC server 0x77777777.
- `0004-iop-bind-rpc-to-ee.patch`: IOP-side `sceSifBindRpc` was a stub that never set `client->server`.
  SNDDRV binds to the game's EE server 0x77777779 (it never calls it) and loops until the bind succeeds.
- `0005-ee-thread-priority-zero.patch`: the EE kernel accepts priorities 0-127. The runtime rejected 0 in
  `CreateThread`/`ChangeThreadPriority`, but its main thread runs at 0 and CRI's ADXM setup creates its threads
  with the main thread's current priority, so CRI's file/stream threads were never created.
- `0006-keep-interrupt-stacks-off-main-stack.patch`: the game's main thread stack is 0x01FF8000-0x02000000, and the
  runtime carved interrupt-handler stacks downward from 0x02000000 too. The vblank/timer handlers overwrote the
  main thread's saved `$ra`, so the main thread "returned" to address 0 right after reading the AFS header.
- `0007-iop-libsd-voice-trans-shim.patch`: SPU2 sound-memory DMA isn't emulated, so libsd's `sceSdVoiceTrans`
  failed and SNDDRV answered every sample upload with -3; the game retried forever. The IOP now reports
  `sceSdVoiceTrans`/`sceSdVoiceTransStatus` as completed (no audio is played yet).
- `0008-ee-change-thread-priority-returns-old.patch`: `ChangeThreadPriority` returned 0 instead of the previous
  priority. CRI's ADX lock saves that value and restores it on unlock, so every unlock raised the caller to
  priority 0 and the busy-waiting main thread starved the ADX streaming threads.
- `0009-debugger-hidden-by-default.patch`: the runtime debugger window starts hidden so the game is visible.
  F1 toggles it; set `PS2X_DEBUG_UI=1` to show it at launch.
- `0010-gs-present-half-height-field-buffers.patch`: the game runs interlaced with SMODE2.FFMD=1 and 512x224
  buffers, while DISPLAY.DH is 448 output lines. The presenter read 448 buffer lines, so the bottom half of the
  window showed texture memory. It now reads (DH+1)/2 lines and line-doubles them.
- `0011-libpad2-hle-and-onimusha3-overrides.patch`: the game reads the controller with libpad2 (DBCMAN/SIO2),
  which the runtime doesn't emulate, so no buttons ever arrived. Adds a small libpad2 HLE fed from the keyboard
  or gamepad, bound to the game's libpad2 functions by a `SLUS_206.94` game override. The same override skips the
  IPU still-image decoder (FUN_0028CE60), which would otherwise stop the runtime on `sceDmaRecvN`.
- `0012-mc-open-create-without-access.patch`: the game creates its save files with `sceMcOpen(..., 0x200)`
  (CREAT, no access bits) and then writes to them. The runtime opened those read-only, so saving failed
  and the game asked to create a save file forever.
- `0013-gif-path3-image-continuation.patch`: `sceGsExecLoadImage` sends the IMAGE GIFtag in one GIF DMA and the
  pixels in the next. The runtime parsed each DMA as a new packet and dropped the pixels, so fonts and CLUTs
  uploaded at boot were missing. PATH3 now carries an unfinished IMAGE over to the next transfer.
- `0014-ee-thread-large-stack.patch`: every guest call is a nested host call, and the EE thread ran on a
  `std::thread` with the platform default stack (1 MB on Windows). On Windows it overflowed (exit code
  -1073741571 / 0xC00000FD) as soon as the sound and streaming threads started. The EE thread now gets a
  256 MB reserved stack, and the main thread 16 MB on MSVC.
- `0015-recompiled-code-overlays.patch`: runtime support for code that is loaded at run time (see
  "Code overlays"). Adds `ps2_overlays.h/.cpp`, a lookup in `hasFunction`/`lookupFunction`, and builds
  `src/runner_overlays/*.cpp` outside the unity batches so overlay changes don't rebuild the main game code.
- `0016-ipu-idec-still-images.patch`: software IPU IDEC (intra MPEG-1/2 macroblocks + colour conversion to
  RGB32) and an Onimusha 3 override that decodes the game's `ipum` still images with it instead of the IPU.
- `0017-dma-recv-and-spr-interleave.patch`: `sceDmaRecv`, `sceDmaRecvN` and `sceDmaRecvI` were unimplemented
  (the runtime stopped with "Unimplemented PS2 stub called: sceDmaRecvN" after the warning screen); they now
  program the channel like libdma. Scratchpad DMA also supports interleave mode (D_SQWC).
- `0018-fpu-sqrt-uses-ft-and-vrsqrt-numerator.patch` (recompiler): `SQRT.S fd, ft` takes its operand from
  the ft field, but the recompiler read fs, so 309 of the game's 511 square roots used the wrong register.
  `VRSQRT` ignored its numerator.
- `0019-ee-thread-context-vf0-constant.patch`: threads created by the game started with VU0 `vf0` = 0
  instead of the hardwired (0,0,0,1), so every VU0 matrix routine that uses `vf0` (unit matrix, quaternion
  to matrix, the `w` = 1 row) produced zeros and gameplay rendered nothing.
- `0020-controller-support.patch`: every connected controller is used (two PS2 ports, hot-plug), with
  SDL GameControllerDB mappings loaded at start-up, a raw fallback for unmapped devices, stick deadzones,
  analog L2/R2 pressure, and the keyboard working alongside controllers. See "Controls".
- `0021-vu1-interpreter-speedups.patch`: the VU1 interpreter (all 3D geometry) is about 2.3x faster with
  bit-identical results: exact-flag checks are skipped when the float result already proves them, pipeline
  queues are only scanned when an entry is due, XGKICK no longer clears a 64 KB buffer per kick, and the three
  VU source files are compiled as one unit so per-instruction helpers inline.
- `0022-gs-rasteriser-thread.patch`: the software GS rasteriser runs on its own thread, alongside the game,
  like the real GS. Anything that reads results back (presentation, VRAM reads, FINISH) waits for queued
  drawing first, so output is unchanged. `PS2X_GS_SYNC=1` runs it on the game thread again (for debugging).
- `0023-iop-speed-and-correctness.patch`: the IOP is run in batches instead of after every EE loop iteration;
  `_wmemcopy`/`_wmemset` (sysclib 40/41) took their size as words instead of bytes and overwrote memory
  (it corrupted SNDDRV's sound-bank state); IOP threads are no longer preempted by threads of the same
  priority (the IOP kernel doesn't do that); and a misaligned load/store with no exception handler is done at
  the aligned address instead of jumping into empty memory.
- `0024-spu2-adma-playback-pacing.patch`: SPU2 AutoDMA (streamed music and movie audio) completes at playback
  speed (48 kHz stereo, 192000 bytes/s) instead of instantly, so CRI's ADX decoder on the IOP runs a hundred
  times a second instead of tens of thousands. Needed with it: a DMA completion interrupt is held while the
  running IOP thread has interrupts suspended (`CpuSuspendIntr`), and that suspended state now belongs to the
  thread instead of being global. Before this, a completion could land in the middle of a driver's critical
  section.
- `0025-gs-presentation-and-parallel-raster.patch`: fixes the "game stops after pressing Start" problem that
  appeared once the IOP stopped slowing the game down. The menu was running, but presentation waited for the
  rasteriser's queue to become *empty* while the game kept filling it, so the window never showed a new frame.
  Presentation now waits only for the drawing queued before it, the game waits when it gets more than a few
  frames of drawing ahead of the rasteriser (as the EE waits for a busy GS), and a caller that needs the
  rasteriser (presentation, VRAM reads) gets it ahead of queued drawing. Runs of primitives that can't affect
  each other through VRAM are split into 16-line bands and rasterised on several threads (one per core,
  leaving one each for the game and the window; `PS2X_GS_THREADS=n` overrides the count). Bilinear texture
  sampling skips texels whose weight is zero (every pixel of a 1:1 sprite), with identical output.
- `0026-vu1-issue-time-register-writes.patch`: the VU1 interpreter writes VF/VI/ACC results when an
  instruction issues instead of queueing them until the end of the pipeline. Every read of a register whose
  result is still in flight already stalls until the result is ready, so no instruction can see the
  difference (checked against the previous interpreter on 300 captured gameplay calls: identical VU memory,
  registers and flags). Flags, Q, P and stores, which are read without interlocks, keep their pipelines.
  With a few smaller changes (vectorised operand normalisation, fewer pipeline scans) VU1 is about 1.8x
  faster again.

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
A further 168 SDK functions (libgraph, libdma, libvu0, libmc, libmpeg/ipu, kernel helpers and libc) come from
`ps2_analyzer`'s signature matching in `onimusha3_analyzer_fallback.toml`, merged where the runtime has a handler.
`sceCdCallback@0x0011C8E0` from that list was left out (it conflicts with the evidence for 0x0011CD98).

Some analyzer bindings were removed on purpose so the game's own (recompiled) code runs instead:
- `malloc_extend_top@0x00122320`: the runtime's handler is a no-op, so `malloc` never got memory and
  `_strtod_r`/`_lshift` looped forever.
- libgraph `sceGsResetGraph`, `sceGsSetDefDispEnv`, `sceGszbufaddr`, `sceGsSetDefDrawEnv`, `sceGsSetDefClear`,
  `sceGsPutDrawEnv`, `sceGsSetDefDBuff`, `sceGsSetDefDrawEnv2`, `sceGsSetDefDBuffDc`, `sceGsSetDefLoadImage`,
  `sceGsExecLoadImage`: the runtime's versions fill simplified private structs, but this game reads those
  structs itself and DMAs them to the GS (texture uploads became garbage and the display pointed at texture
  memory). They are plain packet builders plus GS register writes, so native code is exact. `sceGsSyncV`,
  `sceGsSyncPath`, `sceGsSyncVCallback` and `sceGsResetPath` stay bound (they wait on hardware).

The idle thread at 0x0018B990 (eight `nop`s and a branch back) is deliberately left without a recompiled function:
in this runtime a guest thread that never makes a syscall would never yield.


## Boot progress so far

1. ~~Pink screen: `sceSifInitRpc` waiting for SIF sreg 0~~ (SIF bindings)
2. ~~Pink screen: `sceCdInit` waiting for the CD RPC server~~ (libcdvd/fileio/loadfile bindings)
3. ~~Pink screen: `sceGsSyncV` polling INTC_STAT~~ (libgraph bindings from the analyzer)
4. ~~Sound init waiting for SNDDRV's RPC servers~~ (patches 0002-0004)
5. ~~Black screen: CRI ADXF never reading `IMAGE.AFS`~~ (patch 0005)
6. ~~Main thread exiting after reading the AFS header~~ (patch 0006)
7. ~~Sound upload loop (SNDDRV returning -3)~~ (patch 0007)
8. ~~Main loop running but nothing drawn: ADX threads starved~~ (patch 0008)
9. ~~Scrambled blocks on screen: libgraph struct/packet mismatch, split PATH3 image uploads, half-height field
   buffers~~ (libgraph bindings removed, patches 0010 and 0013)
10. ~~Memory card dialog ignoring input~~ (patch 0011, libpad2)
11. ~~"Create a save file?" loop~~ (patch 0012)
12. Boots through "Checking Memory Card", creates/loads the save, and shows the CAPCOM logo.
13. ~~Logic thread stopping right after the logo: code overlays~~ (patch 0015 + `3b_recompile_overlays.bat`)
14. ~~Black screens instead of the middleware logos and warning~~ (patch 0016)
15. ~~"Unimplemented PS2 stub called: sceDmaRecvN" after the warning screen~~ (patch 0017)
16. Reaches the title screen ("PRESS START BUTTON") and the main menu.
17. ~~Black screen in gameplay: every vertex at 0,0~~ (patches 0018, 0019; libvu0 is no longer replaced by
    the runtime's HLE versions, the game's own routines are recompiled)
18. NEW GAME starts and the 3D gameplay renders.
19. Speed (patches 0021-0026): menus run at full speed. 3D gameplay runs at about 3.5x the speed it had
    before these patches (measured on a 2-core cloud machine: 5.7 -> 15-21 frames per second; a desktop CPU
    with more and faster cores does better, and the rasteriser uses the extra cores). The IOP is now almost
    idle; about three quarters of the game thread's time goes to the VU1 interpreter (3D geometry), which is
    what still keeps gameplay below full speed on slower CPUs.

## Code overlays

Most game code (title screen, menus, areas, enemies) isn't in SLUS_206.94. It lives in 517 Capcom "LINK"
modules (`*.ldt` in `IMAGE.AFS`). Each is a list of entries compressed with CPK0 (LZSS, 4 KB window). Entries
whose data starts with `MWo3` are code modules linked at a fixed address (0x00D00000, or 0x00D20000 for
enemies), with the module name at offset 0x20 (`area108.bin` is the large shared title/game module). The game
copies them into RAM unchanged (no relocation), and many different modules use the same addresses; the 198
empty ELF segments are their placeholders.

`3b_recompile_overlays.bat` recompiles the 188 unique code modules (about 1.7 MB of MIPS). Each module's C++
lives in its own namespace and registers a table of its entry points with the runtime. Patch 0015 adds
`ps2_overlays.h`: when the game branches to an address outside the main function table, the runtime checks
which registered module is resident there (its first 0xC0 bytes in RAM) and runs that module's function.

Overlay code also calls about 70 places in SLUS_206.94 that nothing in the main executable calls, so the
main recompile has no entry for them (for example 0x0018F790). `overlays.ps1 -MainExtra` lists them from the
modules' J/JAL targets and the main function table, `ps2_recomp` recompiles just those from SLUS_206.94, and
they are registered as one extra module covering the main code (always resident), so the main build doesn't
have to change.

Still images (`ipum` entries: logos, the content warning, title backgrounds) are decoded by the IPU's IDEC
command. Patch 0016 adds a software IDEC (`ps2_ipu_idec.cpp`) and uses it in place of the game's IPU strip
decoder. FMV playback (Sofdec, also IPU) is not done yet; the opening movie is skipped as a black screen.

Known gaps: no audio output yet (SPU2 not emulated), IPU-decoded still images and FMVs are not emulated.

## Controls

### Controllers

Any controller Windows sees works, and two can be used at once: the first one is PS2 controller port 1 (shared
with the keyboard), the second is port 2. Controllers can be plugged in or unplugged while the game runs.

- **Mapped controllers** (Xbox 360/One/Series, DualShock 3/4, DualSense, Switch Pro and Joy-Con grips, 8BitDo,
  Logitech, PowerA, most generic USB pads and PS2-to-USB adapters): the layout comes from the community
  [SDL GameControllerDB](https://github.com/mdqinc/SDL_GameControllerDB) (`gamecontrollerdb.txt`, zlib licence,
  see `gamecontrollerdb_LICENSE.txt`). Buttons are positional, like a DualShock 2:

  | PS2 | Xbox | PlayStation | Nintendo |
  |---|---|---|---|
  | Cross / Circle / Square / Triangle | A / B / X / Y | ✕ / ○ / □ / △ | B / A / Y / X |
  | L1 / R1 | LB / RB | L1 / R1 | L / R |
  | L2 / R2 (analog pressure) | LT / RT | L2 / R2 | ZL / ZR |
  | L3 / R3 | stick clicks | L3 / R3 | stick clicks |
  | Select / Start | View (Back) / Menu (Start) | Share/Create / Options | − / + |
  | D-pad, sticks | D-pad, sticks | D-pad, sticks | D-pad, sticks |

- **Controllers without a mapping** use the layout of PS2-to-USB adapters: buttons 1–12 = Triangle, Circle,
  Cross, Square, L2, R2, L1, R1, Select, Start, L3, R3; the hat is the D-pad; axes 1/2 left stick, 3/4 right stick.
  To map one properly, create a mapping line with
  [SDL2 Gamepad Tool](https://generalarcade.com/gamepadtool/) and put it in `gamecontrollerdb_user.txt` in this
  folder (or set `SDL_GAMECONTROLLERCONFIG`).

`run_log.txt` lists each controller as it connects (`[pad] controller 1 connected: ...`), including whether it
was mapped. Rumble isn't supported (raylib's GLFW backend has no vibration). A DualShock 3 needs its Windows
driver (DsHidMini) first. If Steam is running with Steam Input enabled for this program, Steam's virtual Xbox
controller is what the game sees.

### Keyboard

| PS2 | Key |
|---|---|
| Cross / Circle / Square / Triangle | X or Space / C or Esc / Z / V |
| Start / Select | Enter / Tab |
| D-pad | Arrow keys or WASD |
| L1 / R1 / L2 / R2 | Q / E / Left Shift / Right Shift |
| L3 / R3 | Left Ctrl / Right Ctrl |

The keyboard always works, also with controllers connected. Saves go to `game\mc0\BASLUS-20694`.

## After the first boot

These steps follow PS2Recomp's recommended loop:
- Fix hard blockers first: "function not found", syscall TODOs, and missing CD/file stubs.
  The game uses CRI ADX (`CRI_ADXI.IRX`) and Capcom sound drivers (`SNDDRV.IRX`, `MOD*.IRX`). These run through ps2xIOP.
- To bind a stripped function to a runtime handler, add `handler@0xADDRESS` entries to `stubs`. Use
  `ret0@`/`ret1@` only for temporary triage.
- Put fixes that only apply to this game in a runtime game override (`PS2_REGISTER_GAME_OVERRIDE`, see
  `ps2xRuntime/include/game_overrides.h`). Key the override on ELF name `SLUS_206.94`.
- Help and discussion: the PS2Recomp wiki and Discord, linked from the project's README.
