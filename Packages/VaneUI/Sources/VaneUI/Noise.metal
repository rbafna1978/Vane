//  Noise.metal
//
//  The noise field, kept from Direction A's sky shader when the rest of it was deleted.
//
//  It is here because it is the one part of that work that is not about the barograph: value
//  noise with a Hermite interpolation and a four-octave fBm, tuned by looking at the result
//  rather than by copying constants. The instrument scene needs exactly this for surface grain,
//  the clay speckle in the reference, and any cloud that appears behind the apparatus.

#include <metal_stdlib>
using namespace metal;

// MARK: - Noise
//
// Value noise rather than gradient/Perlin. Cloud edges want to be soft and blobby, which is
// exactly what value noise's smoothstepped interpolation gives; Perlin's zero-at-lattice
// property produces a regular grid of dark points that reads as a texture artefact at the
// scale a cloud deck is drawn.

static float hash21(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

static float valueNoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    // Hermite, so the interpolation arrives and leaves each lattice cell with zero slope and
    // the cells do not show up as creases.
    float2 u = f * f * (3.0 - 2.0 * f);
    float a = hash21(i);
    float b = hash21(i + float2(1.0, 0.0));
    float c = hash21(i + float2(0.0, 1.0));
    float d = hash21(i + float2(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

/// Four octaves. Five is not visibly better at this scale and costs 25% more per pixel on a
/// full-screen pass; three leaves the deck looking like lumps rather than cloud.
static float fbm(float2 p) {
    float sum = 0.0;
    float amplitude = 0.5;
    for (int i = 0; i < 4; i++) {
        sum += amplitude * valueNoise(p);
        p *= 2.03;          // not exactly 2: an integer lacunarity re-aligns the octaves' lattices
        amplitude *= 0.5;
    }
    return sum;
}
