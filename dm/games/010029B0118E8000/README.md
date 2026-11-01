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

## Experimental sampler quality (fork branch only; **acceptance incomplete**)

The separate experimental branch `codex/nfs-graphics-experimental-20261101`
adds an **off-by-default build-time test** of NFS 1.0.3's texture sampler
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
These are separate in-review contributions; none is included here.

**Validation needed before requesting upstream review:** complete repeated
in-game runs of both variants; compare the same image area (road, walls, fences and cars), FPS,
frame-time percentiles, GPU time, artifacting and stability. Test both
console modes without changing any game assets. Never commit game files,
original NSOs, RomFS, keys, extracted shaders or user saves.

### Local verification on 2026-11-01

The local retail NSO passed the loader's segment hashes and matched the
registered build. Capstone confirmed `c01240bd` (`ldr s0,[x22,#0x10]`) at
`0x7efe80` and `0001231e` (`ucvtf s0,w8`) at `0x7efec0`. The previous
`0x7eff80`/`0x7effc0` offsets are not these instructions; the original-byte
assertion rejected them before output was written. The corrected enabled
and disabled images have equal size and differ only in the two intended
instruction words. The independent frame-limiter cut is unchanged.

The original three sampler unit tests pass. The sampler, patch registry,
documentation and environment-switch checks pass together (31 tests).
A real build-script rewrite sequence `0 -> 1 -> 0` produced cut counts
`1 -> 3 -> 1`; its disabled cache keys matched and its enabled key differed.
The Python lint ratchet reports zero new findings. Full tool-test discovery
still has unrelated Mac icon-fixture setup failure and one short synthetic
benchmark failure; this is not a claim that the complete suite is green.

Xcode 27.2 (27B52) was installed alongside 27.1 on the development drive;
Apple signature and system trust checks passed. Metal 32023.922
(`metalfe-32023.922.4`) matches `dmsh_chain.lock`. The full Mac build produced
all 2,154 shader libraries for chain `a7dbbce711c3`, then the host and the
pipeline prebuild. Both flag values built through the normal NSP script.
The preserved original build and save were not used as build outputs.
On this Mac, Swift traps with this development environment's Unicode `TMPDIR`;
an ASCII temporary folder on the same drive avoids that compiler issue.

The first gameplay pair reused the older matching host and shader cache.
It is **invalid for a sampler performance comparison**: the disabled run
used roughly 72 Hz acquires without virtual ticks on the 144 Hz screen,
while the enabled run used the intended 60 Hz virtual ticks. The disabled
run repeatedly accumulated seconds of pacing debt, including a 21.733 s
frame ending at 546.413 s. The 540-600 s selector includes frames by their
ending timestamp, so that frame also spans time before the window. Do not
remove it and present the remaining rows as a quality/performance gain.
Both variants did reach a race and exit gracefully with the same three
known red lines. Their screenshots are at different track positions.

The controlled rerun uses one frozen, newly built host, matching shaders,
separate starting-save copies and explicit `DM_LINK_VTICK=1`,
`DM_PRESENT_LINK=1`, `DM_PRESENT_HZ=60`, target 60 fps and scale 1.
Screenshot and sampler-state requests are after the 540-600 s measurement
window. GPU utilization is sampled from the system once per second; it
includes other desktop work and is separate from per-frame GPU duration.
Normal guest time and frame-stamped input can still yield different race
positions, so isolated matching scene captures and repeated trials remain
necessary before claiming a texture-detail improvement or a performance
change. Raw logs, screenshots, NSOs and saves stay local.

### Runtime sampler confirmation and capture limits

A one-frame pass trace after the measurement window confirms that the
experiment reaches real bound samplers: stock captured bindings include
`bias=0/-0.9/-0.45, aniso=1`; enabled captured bindings use
`bias=-0.375, aniso=8`. These are binding records, not a count of unique
samplers. A fixed bias is not an increase in detail for every material:
stock samplers with a more negative bias can select differently in the
opposite direction. The experiment does not provide an anisotropy floor;
it replaces the game's computed value with 8.

The first new-stack pair was also rejected for comparison after visibility
analysis: the enabled window entered fullscreen and became covered at
about 330 s, after which its frames were discarded and the requested PNG
never completed. The disabled run also had an earlier covered interval.
`DM_WINDOW_TOP=1` does not make a floating window visible in every macOS
Space. A fixed-window rerun therefore also sets `DM_FULLSCREEN=0` and
checks the visibility log, actual presented-frame rows and the PNG.
The user restored the game to the current desktop before valid captures.
Do not interpret the covered-window 23-25 fps fallback rows as the cost of
anisotropic filtering. Failed attempts remain in the private evidence.

### Fixed-window exploratory pair

Both selected runs remained visible and exited gracefully: enabled first,
then a disabled recheck, one approximately ten-minute launch each. The
window is 540-600 s, target 60 fps, scale 1, audio on; the same host SHA-256
`2706c4157de4079dc08e5abbb5301f581fd5ea626b655b9d1b3a695f455fd809`
and chain `a7dbbce711c3` were used. No capture is inside that window.

| Variant | FPS | Frame P95 | Frame P99 | Frame max | >25 ms | Dropped | GPU P50 | GPU P95 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| disabled | 59.9 | 21.12 | 21.28 | 102.06 | 9 | 0 | 5.22 | 7.8 |
| enabled | 59.9 | 16.95 | 17.21 | 66.94 | 6 | 0 | 4.94 | 5.59 |

Times are milliseconds. This is an exploratory pair, not evidence of a
performance improvement: the normal-clock input replay reached different
positions and camera directions. The disabled screenshot shows 5.9 miles
remaining at race time 1:35.20; the enabled one shows 6.5 miles at 1:21.33.
System GPU utilization medians were 53.0% disabled and 44.0% enabled;
these include other desktop work. Both had the three known graphics/device
red lines. Enabled also had three brief audio callback-loss/retry reports,
with callbacks later resuming: audio continuity is not fully validated.
Neither run logged a crash. The capture shows rendered cars, road and
vegetation; it does not establish a matched-pixel texture gain or reduced
motion shimmer. Source and start saves remained unchanged by hash comparison.

### Texture detail and anti-aliasing roadmap (not implemented)

The sampler experiment above is **not an HD texture pack**: it can select
existing mip levels differently but cannot manufacture missing texture detail.
Higher-resolution source textures would require a separately verified, legally
redistributable asset pipeline. No texture assets are distributed here.

Anti-aliasing is also **not implemented by this experiment**. MetalFX
presentation upscaling and sharpening are not equivalent to verified
per-game FXAA, SMAA or temporal anti-aliasing (TAA). First test the
existing native game image for jagged edges and temporal shimmering;
then evaluate nxnative internal-resolution supersampling (#405) for
edge quality and cost. Any post-processing AA needs a separate,
reversible implementation, with explicit UI/HUD and motion-artifact
checks. TAA requires game-appropriate temporal inputs and cannot be
assumed available from a final presentation image.

The acceptance conditions for future changes are a verified picture
difference, no new missing surfaces or crashes, stable game simulation,
and frame-time / GPU-time comparisons against a capture-free baseline.
Keep each rendering feature and each verified bug fix in its own PR.
