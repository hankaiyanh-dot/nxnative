# NFS Hot Pursuit Remastered: external AA research and acceptance gates (2026-11-02)

**Status: research and experimental source only; no native Metal build or Mac M6 game run was performed for this branch.**
This research note belongs only to `codex/nfs-ssaa-resolve-20261102`, based on the independently verified resolution branch `codex/nfs-resolution-aa-20261101` (`f0b5cb32`). It does not replace the validated first-stage sampler experiment, the original NFS profile, or upstream benchmark Draft PR #852.

## What other projects actually implement

| Project / source | Relevant implementation | Fit for nxnative NFS | Caveat |
|---|---|---|---|
| [Ryujinx area scaling, PR #7304](https://github.com/Ryujinx/Ryujinx/pull/7304) ([source mirror](https://github.com/Ryojinx/Ryojinx/blob/main/src/Ryujinx.Graphics.Vulkan/Effects/Shaders/AreaScaling.glsl)) | Per-output-pixel **area-weighted** coverage of source texels. The source explicitly credits Sam Belliveau and Filippo Tarpini as public-domain authors. | Best reference for both 2x and 1.5x true downsampling, especially uneven fractional coverage. Implement natively in Metal if quality exceeds simpler filters. | Original runs in a separate compute scaling stage; nxnative currently uses its existing present draw. Preserve flip/crop and color-space semantics; test GPU cost. Do not blindly paste an entire different rendering pipeline. |
| [nxnative PR #345](https://github.com/seedds/nxnative/pull/345) | A bounded multi-tap box filter for downscaled MetalFX output, plus **independent** contrast sharpening. | Closest architecture to current `present.metal` and UV buffer; useful to compare kernel shape, tap count and GPU budget. | #345's supersampling is reconstruction above the viewport, not necessarily the game's **true internal** 1.5x/2x renderer. Sharpening is not antialiasing. Its selector replaces box filtering when enabled; do not conflate both. |
| [Godot: 3D AA](https://docs.godotengine.org/en/stable/tutorials/3d/3d_antialiasing.html) and [resolution scaling](https://docs.godotengine.org/en/stable/tutorials/3d/resolution_scaling.html) | Separates high-res SSAA, FXAA, TAA, MSAA and FSR2; explicitly treats >1.0 internal resolution scale as SSAA. | Validation taxonomy and user-exposed options; compare stationary jagged edges, high-contrast guardrails, texture shimmer, ghosting and UI. | Engine-owned motion/depth/material inputs are not proven available at the final nxnative present. SSAA and FXAA can blur. |
| [SMAA by iryoku](https://github.com/iryoku/smaa) ([license](https://github.com/iryoku/smaa/blob/master/LICENSE.txt)) | MIT-licensed, lookup-based, multi-pass morphological edge AA; area/search tables required. | A future isolated, toggleable post-process if downsampling alone leaves significant edge artifacts. | Requires separate Metal implementation and texture resources; keep full attribution, verify alpha/UI handling and extra passes. This branch does not include SMAA. |
| [NVIDIA FXAA 3.11](https://github.com/CesiumGS/cesium/blob/0becdbfc/packages/engine/Source/Shaders/FXAA3_11.glsl) | Screen-space color-based single-pass antialiasing; sample carries NVIDIA copyright / redistribution terms. | Easier lower-cost candidate after downsampling baseline. | May soften lettering and textures; preserve source copyright and terms if adapted. Not temporal AA. |
| [Apple MetalFX temporal AA](https://developer.apple.com/videos/play/wwdc2022/10103/) | Jittered rendered color + motion vectors + depth, history accumulation and scene-cut reset. | Only if a game-correct temporal-input contract is later established. | Unavailable from an arbitrary color-only swapchain texture; **do not** claim MetalFX spatial scaling provides TAA. |
| [NVIDIA GPU Gems 2, chapter 21](https://developer.nvidia.com/gpugems/gpugems2/part-iii-high-quality-rendering/chapter-21-high-quality-antialiased-rasterization) | Explicitly describes supersampling plus reconstruction / separable downsampling filters. | Review broader filter support before claiming box samples are necessarily best. | Separable filters have different intermediate textures/passes and costs. |

## Current branch's tentative prototype, NOT yet a product feature

Two source commits preceding this note added:
- `dm/gfx/msl/present.metal`: computes footprint by derivatives of present crop UV; retains the original one-sample path at <= 1.25 source texels per output pixel; otherwise uses a box-like grid with **at most 4x4 texture lookups**, clamped to crop edge.
- `dm/tools/tests/test_nfs_present_ssaa.py`: CPU reference arithmetic and static-source assertions only.

The code is intentionally isolated to the experimental branch. **It has not been compiled by Xcode or run in Metal**, and the lightweight Python checks are not a shader compiler or visual acceptance test. There is not yet a runtime enable/disable selector in this implementation, so it MUST NOT be merged into upstream or advertised as an opt-in setting. Switching to the known-good resolution branch is the safe rollback.

Additional review findings from external implementations:
1. At **1.5x**, fixed equally weighted taps approximate rather than exactly integrate unequal source-pixel coverage. An area-weighted filter as used by Ryujinx is the stronger correctness reference; test fractional edges and crop boundaries before adoption.
2. Verify derivative footprints for noninteger scales, orientation, asymmetric X/Y crops, flipped Y, display scaling and viewport subrectangles; source size need not equal swapchain crop size. Derivatives and filtered texture reads in divergent branches should be audited under the Metal compiler and GPU.
3. Test interpolation and mip-level behavior, source texture format, sRGB/linear filtering, alpha and HUD. The source sampler may perform implicit mip filtering, which affects how a multi-tap kernel behaves.
4. The current 4x4 maximum bounds work, but is **not** mathematically equivalent to integrating all source pixels when a source-to-output ratio exceeds 4; comparison at 1x, 1.5x, 2x is the immediate target.
5. Rendering NFS at 3840x2160 on the GPU is verified on the predecessor branch. A final screen image actually resolving its extra spatial samples is **not** proven merely by a higher internal allocation.

## Next acceptance gate on the Mac M6 (all measurements real, no interpolation)

1. Confirm `git status`, build current experimental Metal shader with the repo's locked MSL toolchain; correct any compiler/Metal validation failures. Do not overwrite user files or change the confirmed NFS benchmark PR.
2. Build a synthetic high-contrast diagonal edge, thin fence / checkerboard, and subpixel strip reference (all original, no game assets), compare 1x, fractional 1.5x and 2x sampling with a CPU area-coverage oracle. Include different crop edges/flip orientations.
3. Add a **disabled-by-default runtime selector and independently selectable single-bilinear fallback** before game use, with a configuration and test verifying both paths. No setting yet exists on this branch.
4. Use identical starting saves / recorded-route controls, actual fullscreen/window visibility logs, fixed host and shader hashes. Capture after the measurement window; compare matching track frames and static menu frames separately.
5. Compare road-edge and guardrail jaggies, vegetation / reflective highlight shimmer over time, HUD integrity, frames and P95/P99, GPU time, residency / thermal state and crash indicators; repeat controlled pairs before making claims.
6. Keep all commercial assets, modified NSOs, game keys, saves, original screenshots and raw logs private. Attribute all borrowed code; only redistribute code/assets with verified compatible licensing. Keep upstream PR #852 and first two experiments unchanged.

**Decision:** use Ryujinx area sampling as the correctness reference; compare it with nxnative PR #345's simpler bounded taps. Only consider SMAA or FXAA in a *separate* change if image evidence shows persistent artifacts. Defer TAA until motion/depth/jitter availability is proven.
