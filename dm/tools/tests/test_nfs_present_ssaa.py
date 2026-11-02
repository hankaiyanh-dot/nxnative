"""Asset-free CPU reference checks for an experimental Metal present resolve.

The tests validate only the tap-grid arithmetic and source-level safeguards.
They do NOT compile Metal, prove actual in-game SSAA, or measure performance.
The M6 must compile and inspect identical-scene captures before acceptance.
"""
import math
from pathlib import Path
import unittest


PRESENT = Path(__file__).resolve().parents[2] / "gfx" / "msl" / "present.metal"


def reference_taps(source_texels_per_screen_pixel):
    """Mirror the Metal fragment's bounded box sampling axis."""
    f = source_texels_per_screen_pixel
    if f <= 1.25:
        return [0.0]
    n = max(1, min(math.ceil(f), 4))
    return [((i + 0.5) / n - 0.5) * f for i in range(n)]


class PresentResolveTests(unittest.TestCase):
    def test_single_tap_at_one_to_one(self):
        self.assertEqual(reference_taps(1.0), [0.0])
        self.assertEqual(reference_taps(1.25), [0.0])

    def test_2x_taps_cover_four_source_pixels(self):
        self.assertEqual(reference_taps(2.0), [-0.5, 0.5])

    def test_fractional_shrink_is_symmetric(self):
        self.assertEqual(reference_taps(1.5), [-0.375, 0.375])
        self.assertAlmostEqual(sum(reference_taps(2.25)), 0)

    def test_bounded_filter_cost(self):
        for f in (1, 1.5, 2, 3, 4, 8, 100):
            taps = reference_taps(f)
            self.assertLessEqual(len(taps), 4)
            self.assertAlmostEqual(sum(taps), 0.0)

    def test_crop_abi_and_fallback_still_present(self):
        source = PRESENT.read_text(encoding="utf-8")
        self.assertIn("struct Crop { float4 rect; float4 edge; };", source)
        self.assertIn("if (max(footprint.x, footprint.y) <= 1.25f)", source)
        self.assertIn("return t.sample(s, edge_uv)", source)
        self.assertIn("clamp(uv + position * footprint * texel, c.edge.xy, c.edge.zw)", source)


if __name__ == "__main__":
    unittest.main()
