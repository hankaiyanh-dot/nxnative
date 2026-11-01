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

## Experimental sampler quality (fork branch only; **not validated**)

The separate experimental branch `codex/nfs-graphics-experimental-20261101`
adds an **off-by-default build-time test** of NFS 1.0.3's texture sampler
parameters. In a terminal, set `DM_NFS_SAMPLER_QUALITY=1` for the
`scripts/build_ipa_from_nsp.py` build on this branch. Unset the variable or
set it to `0` and rebuild to restore the stock sampler instructions.
The build script's rewrite-cache fingerprint includes this variable so that
toggling it does not silently reuse a previously rewritten NSO.

- `main+0x7eff80`: change a load to a constant texture mip LOD bias of
  `-0.375`, which *may* favor sharper mip levels at distance.
- `main+0x7effc0`: change the computed maximum anisotropy to `8.0`.
- Both modifications are restricted to the registered 1.0.3 NSO build
  `799d1061182c1302e08e706b84ce76e5`; they check the original
  instruction bytes before rewriting and abort on a mismatch.
- The original instruction encodings were reconstructed from published
  assembly comments; **the original NFS NSO has not been inspected in this
  branch**. A successful build, visual change, FPS effect, and stability
  improvement have **not** yet been demonstrated.
- This changes filtering and mip selection, **not the source texture
  resolution**, scene-object LOD, shadow maps, or anti-aliasing. It does not
  bundle any copyrighted assets or encryption keys.
- The original game-specific 60 fps implementation is left unchanged.

**Credits and prior work:** community [1.0.3 pchtxt](https://github.com/cucholix/NX-IPS-romfs-compilation/blob/main/N/Need%20for%20Speed%20Hot%20Pursuit%20Remastered/1.0.3.pchtxt).
For more general solutions, see nxnative [sampler controls #335](https://github.com/seedds/nxnative/pull/335),
[internal resolution scaling #405](https://github.com/seedds/nxnative/pull/405), and
[presentation sharpening #345](https://github.com/seedds/nxnative/pull/345).
These are separate in-review contributions; none is included here.

**Validation needed before requesting upstream review:** compare original NSO
bytes and generated `main.cuts.tsv`; build NFS 1.0.3 both with and without
the flag; compare the same image area (road, walls, fences and cars), FPS,
frame-time percentiles, GPU time, artifacting and stability. Test both
console modes without changing any game assets. Never commit game files,
original NSOs, RomFS, keys, extracted shaders or user saves.
