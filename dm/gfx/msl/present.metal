// The present: the frame drawn into the drawable, cropped (nvn_mtl.m present_pipeline)
#include <metal_stdlib>
using namespace metal;
struct V { float4 p [[position]]; float2 uv; };
vertex V vs(uint id [[vertex_id]]) { float2 uv = float2((id << 1) & 2, id & 2); V o; o.p = float4(uv * float2(2, -2) + float2(-1, 1), 0, 1); o.uv = uv; return o; }
struct Crop { float4 rect; float4 edge; };
// Experimental downsampling resolve on the NFS SSAA branch. The vertex path,
// crop ABI (eight floats) and single-sample present are unchanged. Unlike
// sharpening or MetalFX reconstruction, this averages multiple positions in
// a genuinely larger source image before displaying it at a smaller size.
// The host supplies the footprint and tap counts from the actual source crop
// and picture viewport. UV derivatives vary slightly across quads: ceil() on
// those values incorrectly selected 3/4 taps at integer 2:1/3:1 reductions.
//
// This is a spatial box resolve, NOT FXAA/SMAA/TAA. It does not create samples
// where the game did not render them, or fix motion shimmer on its own.
// A crop edge clamps every tap, as the original sampler path does. Only a
// shrink greater than 1.25 texels/destination pixel takes the multi-tap path.
// Limit to 4 taps per axis so a large source cannot cause unbounded GPU work.
// TODO: compare source/viewport sizes and bilinear vs resolved imagery at
// matching race positions on M6 before claiming any quality benefit.
// The ordinary, single-bilinear present stays the default and is the A/B baseline.
fragment float4 fs(V in [[stage_in]], texture2d<float> t [[texture(0)]], sampler s [[sampler(0)]], constant Crop& c [[buffer(0)]]) {
  return t.sample(s, clamp(in.uv * c.rect.zw + c.rect.xy, c.edge.xy, c.edge.zw));
}

// Experimental multi-tap downsample: selected only through DM_PRESENT_SSAA=1.
fragment float4 fsaa(V in [[stage_in]], texture2d<float> t [[texture(0)]], sampler s [[sampler(0)]], constant Crop& c [[buffer(0)]], constant float4& resolve [[buffer(1)]]) {
  float2 uv = in.uv * c.rect.zw + c.rect.xy;
  float2 edge_uv = clamp(uv, c.edge.xy, c.edge.zw);
  float2 size = float2(float(t.get_width()), float(t.get_height()));
  float2 texel = 1.0f / size;
  float2 footprint = resolve.xy;
  int nx = int(resolve.z), ny = int(resolve.w);
  if (nx == 1 && ny == 1) return t.sample(s, edge_uv);
  float4 sum = float4(0.0f);
  for (int y = 0; y < ny; ++y) for (int x = 0; x < nx; ++x) {
    float2 position = float2((float(x) + 0.5f) / float(nx) - 0.5f,
                             (float(y) + 0.5f) / float(ny) - 0.5f);
    float2 tap_uv = clamp(uv + position * footprint * texel, c.edge.xy, c.edge.zw);
    sum += t.sample(s, tap_uv);
  }
  return sum / float(nx * ny);
}
