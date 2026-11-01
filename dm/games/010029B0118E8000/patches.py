# Need for Speed: Hot Pursuit Remastered (010029B0118E8000): the rewriter's patches of this game's own builds. dm/tools/patch_nso.py loads every profile's patches.py and applies those of a
# module's NSO build ID; CUTS, OBS and FRAME_STEP as described there ("Registered patches"). Patches of Nintendo SDK module builds are in dm/tools/sdk_patches.py
import os

# Opt-in, build-time-only experiment. This environment variable is deliberately
# not a runtime setting: the game's original instructions are changed during
# NSO rewriting. The NSP script includes it in the rewrite cache key.
# Disabled on every ordinary build and in the upstream game profile.
_NFS_SAMPLER_QUALITY = os.environ.get('DM_NFS_SAMPLER_QUALITY', '0') == '1'

CUTS = {
  # 1.0.3 (v196608) main: the frame limiter. The loop at main+0x483588 calls the system tick (main+0x86f070) until the frame's deadline ([x19+0x20] ticks per frame, from the frame
  # count at [x19+0x2c]) has passed, a busy spin at 30 fps. The host paces presents itself (present_interval display) and writes the engine's 60 fps frame time (hle_fpslock.c), so the
  # spin's branch back is cut, as masagrator's FPSLocker config for this build does (FPSLocker-Warehouse, patches/010029B0118E8000/799D1061182C1302.yaml)
  '799d1061182c1302e08e706b84ce76e5': [
    (0x4835a4, '2cffff54', '1f2003d5', 'frame limiter spin: b.gt main+0x483588 → nop (the host paces the frames)'),
  ],
}

# Published 1.0.3 pchtxt reference:
# https://github.com/cucholix/NX-IPS-romfs-compilation/blob/main/N/Need%20for%20Speed%20Hot%20Pursuit%20Remastered/1.0.3.pchtxt
# The old instructions below were reassembled from the source's disassembly
# comments; the actual game NSO bytes have NOT yet been independently checked.
# patch_nso.py compares the original bytes and fails closed on any mismatch.
# Do not copy the pchtxt's separate 60 fps instructions: the host already
# controls frame pacing and the profile already cuts the spin limiter.
if _NFS_SAMPLER_QUALITY:
    CUTS['799d1061182c1302e08e706b84ce76e5'].extend([
        (0x7eff80, 'c01240bd', '00103b1e',
         'opt-in texture mip LOD bias: ldr s0,[x22,#0x10] -> fmov s0,#-0.375'),
        (0x7effc0, '0001231e', '0010241e',
         'opt-in max anisotropy: ucvtf s0,w8 -> fmov s0,#8.0'),
    ])

# How general each patch is and could be (dm/tools/docs_patches.py "Binding", listed in docs/agents/game-patches.md): what, its binding now, the loosest it could have (goal),
# purpose, why; blocked or kept: why the gap stays open (cannot close yet, or left open on purpose); checked: what was checked on game files (else a judgement)
BINDING = [
    {'what': 'frame limiter spin: its branch back cut', 'now': 'build', 'goal': 'game', 'purpose': 'frame rate',
     'why': "the engine's own spin limiter; a function-matched rule could carry it over the game's updates"},
]

if _NFS_SAMPLER_QUALITY:
    BINDING.extend([
        {'what': 'optional NFS 1.0.3 texture mip LOD bias -0.375', 'now': 'build', 'goal': 'game', 'purpose': 'rendering',
         'why': 'an experimental per-build visual choice; needs original NSO byte verification and an NFS visual A/B comparison'},
        {'what': 'optional NFS 1.0.3 anisotropy floor 8x', 'now': 'build', 'goal': 'host', 'purpose': 'rendering',
         'why': 'prefer the general sampler option in PR #335 once reviewed; not a new host feature'},
    ])
