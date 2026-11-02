"""Asset-free checks for the optional NFS 1.0.3 sampler experiment.

These test the profile switch and cut metadata, NOT the original game NSO,
runtime visual effect, graphics correctness, or performance.
"""
import os
from pathlib import Path
import runpy
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[3]
PROFILE = ROOT / "dm" / "games" / "010029B0118E8000" / "patches.py"
SCRIPT = ROOT / "scripts" / "build_ipa_from_nsp.py"
BUILD = "799d1061182c1302e08e706b84ce76e5"


def cuts(flag):
    with patch.dict(os.environ, {"DM_NFS_SAMPLER_QUALITY": flag}):
        return runpy.run_path(str(PROFILE))["CUTS"][BUILD]


class NFSSamplerQualityTests(unittest.TestCase):
    def test_default_unmodified(self):
        with patch.dict(os.environ, {}, clear=True):
            original = runpy.run_path(str(PROFILE))["CUTS"][BUILD]
        self.assertEqual(len(original), 1)
        self.assertEqual(original[0][0], 0x4835a4)
        self.assertEqual(cuts("0"), original)

    def test_opt_in_patches_only_two_sampler_instructions(self):
        normal = cuts("0")
        enabled = cuts("1")
        self.assertEqual(enabled[:1], normal)
        self.assertEqual(
            [(off, before, after) for off, before, after, _ in enabled[1:]],
            [
                (0x7EFE80, "c01240bd", "00103b1e"),
                (0x7EFEC0, "0001231e", "0010241e"),
            ],
        )
        for _, before, after, _ in enabled:
            self.assertEqual(len(bytes.fromhex(before)), len(bytes.fromhex(after)))

    def test_switch_is_in_rewrite_cache_fingerprint(self):
        source = SCRIPT.read_text(encoding="utf-8")
        self.assertIn(
            "('DM_PATCH_FRONT', 'DM_GAME', 'DM_NFS_SAMPLER_QUALITY')",
            source,
        )


if __name__ == "__main__":
    unittest.main()
