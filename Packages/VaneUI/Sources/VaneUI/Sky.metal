//  Sky.metal
//
//  The rendered sky. Everything in here is per-pixel compositing; none of the colour science
//  lives here. Zenith, horizon, sun and cloud colours all arrive pre-mixed from `Palette`,
//  which does its blending in linear light and holds the contrast floor. A shader is a bad
//  place to keep decisions you want to unit-test, so it keeps none.
//
//  Layers, painted back to front: gradient, sun or moon, cloud deck, precipitation.

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

// MARK: - Sky

// `.colorEffect` fixes the first two parameters: the pixel's position in the view's own
// coordinate space, and the colour already there. Omitting the second one does not fail to
// compile — it fails to *bind* at runtime, and the effect is silently dropped, which shows up
// as a plain black rectangle rather than as an error.
[[ stitchable ]] half4 vaneSky(
    float2 position,
    half4 currentColor,
    float2 size,
    float time,
    float2 sun,          // sun/moon position in unit view space, y down
    float elevation,     // degrees above the horizon; negative means the moon is drawn
    float cover,         // 0...1 cloud cover
    float precip,        // 0...1 precipitation intensity
    float wind,          // signed drift, view-widths per second
    half4 zenith,
    half4 horizon,
    half4 light,         // sun or moon disc colour
    half4 cloud
) {
    float2 uv = position / size;

    // 1. Gradient. Squared so the horizon band stays tight and most of the frame is zenith,
    //    which is how the sky actually reads when you look at it.
    half4 color = mix(zenith, horizon, half(uv.y * uv.y));

    // Horizon haze. The last few degrees above the ground are looking through far more
    // atmosphere, so they lighten and lose saturation into a soft band. Without it the gradient
    // stops dead at the bottom edge and the sky reads as a rectangle of paint, which is exactly
    // what it looked like before this line existed.
    float haze = smoothstep(0.55, 1.0, uv.y);
    half3 hazeColor = mix(horizon.rgb, half3(1.0h), 0.32h);
    color.rgb = mix(color.rgb, hazeColor, half(haze * 0.55));

    // 2. The luminary. Distance is corrected for aspect so the disc is round in a tall frame.
    float aspect = size.x / size.y;
    float2 toSun = (uv - sun) * float2(aspect, 1.0);
    float dist = length(toSun);

    bool isDay = elevation > -0.833;   // the sun's disc plus atmospheric refraction
    // Small disc, wide glow. The sun subtends half a degree; almost all of what you see
    // looking at it is atmosphere, not disc, and a large flat disc is the tell of a drawn sun.
    float discR = isDay ? 0.016 : 0.013;
    float glowR = isDay ? 0.95 : 0.30;

    // Glow falls off on an inverse curve rather than a linear ramp; a linear halo has a visible
    // outer edge where it reaches zero, and the sky does not have one.
    float glow = discR / max(dist, 1e-4);
    glow = pow(clamp(glow, 0.0, 1.0), 2.6) * smoothstep(glowR, 0.0, dist);

    // A second, far wider and fainter term. One falloff curve gives the uniform airbrushed
    // circle this looked like on the first pass; real forward scatter is a bright tight core
    // riding on a very broad, very dim wash across most of the sky, and it is the broad term
    // that stops it reading as a sticker.
    float scatter = pow(clamp(discR * 3.4 / max(dist, 1e-4), 0.0, 1.0), 1.15) * 0.22;

    // Antialiased by the pixel's own footprint rather than a guessed constant, so the limb
    // stays crisp at any scale instead of blurring on a large frame.
    float edge = fwidth(dist) * 1.5;
    float disc = 1.0 - smoothstep(discR - edge, discR + edge, dist);

    // Cloud thins the sun rather than erasing it — an overcast sun is a bright patch, not an
    // absence — and the luminary is cut off entirely once it is genuinely below the horizon.
    float visible = (1.0 - cover * 0.75) * step(-6.0, elevation + (isDay ? 0.0 : 90.0));
    color = mix(color, light, half(clamp(glow * 0.5 + scatter + disc, 0.0, 1.0) * visible));

    // 3. Cloud deck. Drifts on wind, and is squashed vertically so the noise reads as a deck
    //    seen in perspective instead of as wallpaper.
    float2 cloudUV = float2(uv.x * 2.4 + time * wind, uv.y * 4.2 - time * wind * 0.12);
    float n = fbm(cloudUV);
    // Second, slower, larger-scale layer. Two decks moving at different rates is the cheapest
    // convincing depth cue there is, and it is what a real sky does.
    n = mix(n, fbm(cloudUV * 0.45 - float2(time * wind * 0.35, 0.0)), 0.45);

    // `cover` moves the threshold, so an 8-okta sky is genuinely solid and a 2-okta sky is a
    // few scattered forms, rather than the same cloud field at different opacities.
    float threshold = mix(0.78, 0.18, cover);
    float density = smoothstep(threshold, threshold + 0.28, n);
    // Clouds thin out at the top of the frame, where you would be looking straight up through
    // less of the deck.
    density *= smoothstep(0.0, 0.35, uv.y);
    color = mix(color, cloud, half(density * mix(0.55, 0.92, cover)));

    // 4. Precipitation. Hashed columns, each with its own phase and speed, drawn as short
    //    streaks raked by the wind. No particle system: a fragment function does this in a
    //    dozen lines and costs nothing to keep on screen.
    if (precip > 0.001) {
        // Hashed 2D cells, raked by the wind.
        //
        // The first version hashed by *column* only: every drop in a column shared one phase and
        // one x, which drew a regular lattice of dashes rather than rain. Hashing the cell in
        // both axes lets each cell decide independently whether it holds a drop, where across
        // its width, and how fast it falls — and that independence is the whole difference
        // between rain and graph paper.
        float rake = wind * 1.6;
        float2 rp = float2(uv.x * 58.0 + uv.y * rake * 9.0, uv.y * 9.0);
        float2 cell = floor(rp);
        float2 f = fract(rp);

        float present = hash21(cell);              // does this cell carry a drop at all
        float across = hash21(cell + 17.3);        // where across the cell it sits
        float phase = hash21(cell + 41.7);         // where in its fall it is
        float speed = 5.0 + phase * 6.0;

        float dx = abs(f.x - (0.12 + 0.76 * across));
        float fall = fract(f.y - time * speed - phase);

        // A drop, not a dash: narrow across, with a tail that fades behind it.
        float streak = smoothstep(0.055, 0.0, dx) * smoothstep(0.42, 0.0, fall);
        // Only a fraction of cells carry a drop at a given intensity, so drizzle and downpour
        // differ in density rather than only in opacity.
        streak *= step(present, precip * 0.85);
        color = mix(color, cloud, half(streak * 0.6));
    }

    color.a = 1.0h;
    return color;
}
