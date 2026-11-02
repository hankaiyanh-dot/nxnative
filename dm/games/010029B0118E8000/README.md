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
#405's `ups_pass` / `ups_rect` helpers. That isolated stage did not import
the sampler experiment or modify benchmark PR #852. The integration below
adds the sampler switch separately; #345 and #335 remain excluded.

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

## Experimental sampler quality (opt-in fork experiment)

The first-stage branch `codex/nfs-graphics-experimental-20261101` introduced
the **off-by-default build-time test** of NFS 1.0.3's texture sampler
parameters. In a terminal, set `DM_NFS_SAMPLER_QUALITY=1` for the
`scripts/build_ipa_from_nsp.py` build on this branch. Unset the variable or
set it to `0` and rebuild to restore the stock sampler instructions.
The build script's rewrite-cache fingerprint includes this variable so that
toggling it does not silently reuse a previously rewritten NSO.

- `main+0x7efe80`: change a load to a constant texture mip LOD bias of
  `-0.375`, which *may* favor sharper mip levels at distance.
- `main+0x7efec0`: change the computed maximum anisotropy to `8.0`.
- Both modifications are restricted to the registered 1.0.3 NSO build
  `799d1061182c1302e08e706b84ce76e5`; they check the original
  instruction bytes before rewriting and abort on a mismatch.
- The original instructions were checked against the locally owned retail
  1.0.3 NSO on 2026-11-01 using the hash-validating module loader and
  Capstone disassembly. The published pchtxt offsets include a `0x100` NSO
  header; the rewriter uses loaded memory offsets. The earlier offsets
  correctly failed the original-byte assertion. Both corrected variants
  now rewrite successfully; their images differ only at the two intended
  instructions. Runtime acceptance remains separate from this byte check.
- This changes filtering and mip selection, **not the source texture
  resolution**, scene-object LOD, shadow maps, or anti-aliasing. It does not
  bundle any copyrighted assets or encryption keys.
- The original game-specific 60 fps implementation is left unchanged.

**Credits and prior work:** community [1.0.3 pchtxt](https://github.com/cucholix/NX-IPS-romfs-compilation/blob/main/N/Need%20for%20Speed%20Hot%20Pursuit%20Remastered/1.0.3.pchtxt).
For more general solutions, see nxnative [sampler controls #335](https://github.com/seedds/nxnative/pull/335),
[internal resolution scaling #405](https://github.com/seedds/nxnative/pull/405), and
[presentation sharpening #345](https://github.com/seedds/nxnative/pull/345).
The resolution implementation from #405 is included by the second-stage
integration above. The general controls from #335 and the presentation
changes from #345 are not included in this integration.

**Validation needed before requesting upstream review:** complete repeated
in-game runs of both variants; compare the same image area (road, walls, fences and cars), FPS,
frame-time percentiles, GPU time, artifacting and stability. Test both
console modes without changing any game assets. Never commit game files,
original NSOs, RomFS, keys, extracted shaders or user saves.

The isolated sampler validation and its limitations are recorded in
[the first-stage source note](https://github.com/hankaiyanh-dot/nxnative/blob/86d9ac6b2820ab2765d3b3ab754f8937f8ace3a5/dm/games/010029B0118E8000/README.md#local-verification-on-2026-11-01).
The integration branch combines this build-time switch with the resolution
control above. The combined validation is recorded below.

## Integrated sampler and resolution trial (2026-11-02, experimental fork)

Branch `codex/nfs-integrated-graphics-20261102` starts from published
resolution commit `f0b5cb32d6c1bedd6e2cac418256f4d9b098f088` and ports only
the sampler profile, synthetic tests, rewrite cache key and documentation
from `86d9ac6b2820ab2765d3b3ab754f8937f8ace3a5`. Defaults remain stock
samplers and 1x resolution. Both original branches and benchmark PR #852
are unchanged. The uncommitted phase-three presentation-filter work stays
in its separate checkout; it is not part of this trial.

The clean integration host was rebuilt using Xcode 27.2 and Metal
32023.922 (`metalfe-32023.922.4`), including 13 precompiled host Metal
libraries. Game libraries reuse the verified `a7dbbce711c3` chain and
`7f44b09e6198` inputs with authentic matching companion tables; no stamp
was edited. Original NSO segment hashes and instruction words were
rechecked. The real build-script rewrite `0 -> 1 -> 0` gives 1/3/1 cuts,
matching disabled cache keys and modules, a distinct enabled key, and
only the two intended sampler instruction words differing. Source game
modules and original/starting saves remain unchanged.

For a static comparison, retain only the existing route's first eleven
menu inputs, ending at `f19404:A~f12`, and omit all driving inputs. The
final captures show zero speed at the Grand Ocean Road start area,
8.4 miles remaining. One run each, stock1 then sampler1 then combined2;
target 60 fps, scale 1, audio on, normal guest clock, windowed and visible,
explicit 60 Hz virtual ticks, HUD/MetalFX/sharpening off. The 350-380 s
window has no screenshots or dumps. A preview is at 338 s; final captures
are at 382/384/386 s and a sampler/pass trace is after 387 s.
`DM_NVN_SHOT_OUT=1280x720` captures the actual presentation filter at a
fixed size matching the drawable, rather than the pre-filter source.

| Variant | FPS | Frame P95 | Frame P99 | Frame max | Frame >25 ms | GPU P50/P95 | System GPU median % | Shown >25 ms |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| stock1 | 60.0 | 21.85 | 22.23 | 22.69 | 0 | 4.93/7.04 | 52 | 45 |
| sampler1 | 60.0 | 21.91 | 22.2 | 50.51 | 1 | 5.0/7.17 | 52 | 63 |
| combined2 | 60.0 | 21.53 | 21.86 | 22.59 | 0 | 7.65/8.67 | 60.0 | 41 |

Times are milliseconds. All three exit gracefully, with zero discarded
present rows and the same two known unknown-device-item messages
(0x60/0x61). Positive shown intervals include 27.8 ms intervals on the
144 Hz display: zero discarded presents does not mean uniform display
pacing. No timing row is removed. System GPU samples are restricted to
the timing window and include other desktop work. One stationary trial
per variant does not establish a performance gain or a driving workload
cost; no interleaved repetition, long thermal trial or audible-audio
verification is claimed.

Runtime binding records confirm stock bias 0/-0.9/-0.45 with aniso 1,
and enhanced bias -0.375/aniso 8, including combined2. The combined
race pass uses 3840x2160 attachments while the output remains 1280x720.
Visual checks accept an approximately matching stationary start-line view.
The combined early preview shows 5 mph before settling; final selected pole
dark-core centers differ by at most 0.22 pixels from stock1. This neither
proves final displacement nor locks the exact pose. Race clocks differ by
about 1.7 seconds. Final sequences retain their geometry, but reflections,
lighting, tail lamps and HUD time animate. This is a visual-integrity
comparison, not identical simulation inputs or a causal image-quality test.
Road filtering changes are visible; fixed bias is not sharper for every
material, and residual fine-wire/edge aliasing remains. No texture pack,
shadow or object-LOD change is added, and there is no motion-AA claim.

A compressed-menu pilot stayed at the map and was rejected, including
all its timing. That first fresh-worktree build used runtime host-shader
compilation and lacked companion tables; the accepted runs use the
precompiled host and authentic matching tables above.

Checks: 47 sampler/registry/docs/environment/launcher tests pass; Python
lint has 391 baseline findings, zero new or stale findings. `t_ups` has
zero failures; `t_nvn` 218, `t_clear_ds` 48 and `t_present_crop` 88 checks
pass. No shader translator or broad host-source change is added to the
resolution base; earlier cross-game/harness limits still apply. No full
Python or cross-game regression pass is claimed.

Next AA experiment: evaluate the already isolated #345-derived box
downsampling without sharpening, using identical high-resolution input
frames and a 3:1 reduction as observed here. The current single bilinear
presentation sample does not average the full 3x3 source footprint.
A correct spatial supersampling resolve is the next candidate; higher
internal resolution alone is not accepted as completed SSAA. A dynamic
sequence is still needed to judge shimmer; no TAA input contract has
been established. The #335 general sampler controls remain a separate
future replacement for this build-specific experiment.
