# Need for Speed: Hot Pursuit Remastered (`010029B0118E8000`)

Update 1.0.3 (v196608) over the base game (v0), SDK 10.4.1. Criterion's engine (ported by Stellar Entertainment) on NVN, with Bink movies and Criterion's Bundle 2 (`.BNDL`) files. Modules `main`, `subsdk0` (GLSLC, NVN's runtime shader compiler; not loaded, nothing calls it), `subsdk1` (NintendoSDK_movie) and `sdk`.

Status: plays on the Mac (Apple M4, 2026-10-28): boot, the Autolog connection screen (offline, it goes on by itself), the career map, car select and whole races (Grand Ocean Road, Mystic Lake Road, South Face Drive, First Offence with the gold medal), at 60 fps with sound, a Switch Pro Controller and saves. In two sessions of 7 and 11 minutes: no crash, no new red line; at 60 fps 81% of the 300-frame windows held 16.7 ms (the others, menus and loading screens, 18 ms), 0.37% of the frames dropped, GPU 6.3 ms a frame (p50), the main thread about 4 ms. iOS has not been tested.

## What it needs

| Setting | Where | Why |
|---|---|---|
| The shaders of `SHADERS.BNDL` | `shader_split.py` `bnd2_shaders` | the 2,112 GLSLC outputs are in zlib resources of a Criterion Bundle 2 ([GLSLC outputs in Criterion's Bundle 2 resources](../../../docs/reference/shaders.md#glslc-outputs-in-criterions-bundle-2-resources)) |
| `fps_target 60`, `present_interval display` | [`game.tsv`](game.tsv), `hle_fpslock.c` | 60 fps (30 on the Switch), see [Frame rate](#frame-rate) |
| The frame limiter's spin cut (`main+0x4835a4`) | [`patches.py`](patches.py) | the engine's own 30 fps wait |
| `enc_thread on` | `game.tsv`, `nvn_rec.h` | the game waits on its fence every frame; see [Frame rate](#frame-rate) |

The rest of the profile is what `profile_guess.py` made of the survey: the 3.25 GB heap of the hardware pool, no virtual address memory.

## Frame rate

- **Current: 60 fps.** The engine has a 60 fps mode: a uint32 at `main+0xf0043c` (0 at boot) makes it take its frame time from the timer object at `[main+0xed96a8]` (+0x30 the frame in system ticks, +0x28 a tenth of it) and step the game by the floats at `[main+0xeffc60]` +0x30 (2D) and +0x50 (3D). All of these already hold 60 fps values when the game runs (320,000 ticks, 1/60 s): the host writes the mode switch (`hle_fpslock.c`, `MODE_U32`) and keeps the others at the target (`TICKS_U32`, `SECS_F32`; at 30 it writes 640,000 and 1/30). At 30 fps the frame limiter (`main+0x483530`) spins on the system tick (`main+0x86f070`) until `[x19+0x20]` ticks per frame have passed; the rewriter cuts its branch back (`main+0x4835a4`), and the host paces the presents (`present_interval display`; the game asks for interval 2). From masagrator's FPSLocker config for this build (FPSLocker-Warehouse, `patches/010029B0118E8000/799D1061182C1302.yaml`; the frame-time instruction found by theboy181); each value was checked in the running game before writing.
- **Resolved: 18.1 ms frames (55 fps) in races at 60.** The game calls `nvnSyncWait` twice a frame on a fence it places after its submission, so with Metal encoding on the submit thread the frame was the game's work (about 4 ms) plus the host's encoding (2.5 ms) plus the GPU (6.3 ms) in series. A lower frame-tick target (66, 80, 120 fps) and handheld mode (GPU 5.4 ms) changed nothing; with `DM_NVN_ENC_THREAD=1` the race frames hold 16.66 ms (p95 16.9–17.5). The profile's `enc_thread on` makes that the Mac default for this game.
- Game speed at 60 was checked by play: races, the timer and the AI run at normal speed.

## Rendering

- **Resolved: a crash at the first loading screen** after `texture upgraded to allow format views` (a 4096x1024 texture, base format 73, sampled as format 70): the upgrade's copy ended the render pass while the draw bound its arguments ([A texture upgrade while a draw binds its arguments ends the pass](../../../docs/reference/rendering.md#a-texture-upgrade-while-a-draw-binds-its-arguments-ends-the-pass)).
- **Current:** `vertex attribute format 0x27 (8 / 16-bit integer) feeds a float input`, converted on the CPU at replay; no visible effect.
- `nvnDeviceGetInteger` items 0x60 and 0x61 are answered 0, as before; no visible effect.

## Services

- Autolog, the game's online layer, finds no network (`nifm` answers as offline) and the game goes on to the career map after its connection screen.

## Found on this game

General changes first needed here; each applies to every game:

- [GLSLC outputs in Criterion's Bundle 2 resources](../../../docs/reference/shaders.md#glslc-outputs-in-criterions-bundle-2-resources) (`shader_split.py`)
- [A texture upgrade while a draw binds its arguments ends the pass](../../../docs/reference/rendering.md#a-texture-upgrade-while-a-draw-binds-its-arguments-ends-the-pass) (`nvn_mtl.m`)
- `hle_fpslock.c`: frame times in system ticks, frame steps in seconds and a mode switch as frame-limit fields; the profile key `enc_thread`


## Internal-resolution experiment: NFS on Mac M6 (2026-11-01, fork only)

The independent branch `codex/nfs-resolution-aa-20261101` starts from upstream
`dad38db62ef549404b617a73aa18d31aa8117c8e` and reuses
[PR #405](https://github.com/seedds/nxnative/pull/405), head
`c07feb3dcdcd12adbc157ab1ab2e070ecde39a6f` by Amost-.
The one integration conflict retains both main's `att_layers` clear helper and
#405's `ups_pass` / `ups_rect` helpers. It does not import the separate sampler
experiment or modify benchmark PR #852. #345 and #335 are not included.

Mac mini Apple M6, 16 GiB, macOS 27.2 (26B123), Xcode 27.2. One normal-clock
Roadsters Reborn / Boxster route trial per factor, in the order 1, 1.5, 2;
60 fps target, render scale 1, audio on, windowed, explicit 60 Hz virtual ticks,
present-time upscaling off, HUD off. Each launch lasts about ten minutes; the
540-600 s measurement contains no screenshots or pass dumps. A screenshot is
requested at 600.5 s. Copies of the same private starting save are used and the
source starting save remains unchanged by SHA-256. The host is rebuilt here;
the previously verified stock-sampler rewritten modules and matching
`a7dbbce711c3` game shader libraries are reused, not rebuilt from NSP this round.
All three runs remain visible, reach the race and exit gracefully.

Times below are milliseconds. These are exploratory observations, not a causal
performance comparison: normal-clock replay reached different race positions.

| Factor | FPS | Frame P95 | Frame P99 | Frame max | >25 ms | GPU P50 / P95 | Dropped |
|---|---:|---:|---:|---:|---:|---:|---:|
| 1x | 59.9 | 21.42 | 22.08 | 74.39 | 7 | 5.2 / 7.84 | 0 |
| 1.5x | 59.9 | 21.58 | 22.23 | 64.02 | 10 | 5.12 / 8.69 | 0 |
| 2x | 59.9 | 21.46 | 21.95 | 78.86 | 6 | 6.16 / 6.84 | 0 |

Allocation logs and original screenshots confirm selected 1920x1080 targets
become 2880x1620 or 3840x2160. At 2x, pre-window and post-window pass traces
also contain real 3840x2160 color attachments; square targets remain unscaled.
No resolution-demotion log was observed. Same-event intro screenshots show no
obvious missing geometry or UI clipping; race captures contain the car, road,
shadows and HUD. They do not establish a motion-AA improvement, matched-position
shadow/reflection correctness, or correctness of every render pass. Mirror
fine-line patterns remain a visual-review limitation.

System GPU utilization medians in the window are 46 / 44 / 45 percent (29 / 30 /
29 samples, about every two seconds); this includes desktop work. Process RSS
window medians are 0.8333 / 0.8464 / 0.8827 GiB. RSS is not the full unified-memory
footprint; system GPU allocations must not be added to it as independent memory.
No thermal/performance warning was reported by `pmset -g therm`, and sampled
swap use stayed 218.31 MiB. Temperatures and watts were not measured. This is
not a sustained thermal or long-duration stability certification. Audio callback
logs have no reported retry/loss or nonzero underrun; audible quality was not
independently assessed.

Validation: host build succeeds; `t_ups` has zero failures; `t_nvn` 218 checks,
`t_clear_ds` 48 checks, zero failures; launcher/settings/environment tests 17
and docs tests 11 pass. Host MSL generation fell back to embedded source in this
build, and deswizzle/present libraries compiled at startup before the window;
compiler warnings remain. The 1.5x post-window diagnostic mistakenly used
`passes 1`, rejected as an unknown key; it was corrected to `passdump 1` for 2x.
Thus 1.5x has allocation/screenshot evidence but no accepted pass trace in this
trial. No timing rows were discarded. The regression harness command
`scripts/regress.py check --games 010029B0118E8000 --quick` stops because its
root/games directories are not configured. Only NFS is installed here; no
cross-game regression, complete graphics suite, or lint-ratchet pass is claimed.
This remains an experimental fork, not an upstream-ready replacement for #405.

AA audit: one prior NFS race trace contains 529 single-sample pipelines; local
shader metadata also names `DriveableSurfaceAntialiasControl`. Neither proves
the complete native post-processing AA path. No verified FXAA/SMAA/TAA path or
usable temporal-input contract is established. This #405 tip excludes multisample
targets from scaling. The current present shader takes one bilinear sample, so
higher internal resolution is not a validated complete SSAA resolve. Sharpening
and spatial MetalFX reconstruction are not counted as AA. No new AA is added;
whole-scene edge quality and motion shimmer remain open, with #345's output
filtering a separate candidate for evaluation.

An independent read-only integration review found no merge-specific blocker.
It flagged an inherited #405 caveat: `ups_demote_pass` considers configured
attachments before `clear_only` / `g_geo_omit_colors` filters, potentially demoting
an unused scaled target. This was not demonstrated on NFS and is not patched here.
Raw game files, shaders, saves, logs and screenshots stay local; only source,
synthetic tests and this sanitized note belong in the fork.
