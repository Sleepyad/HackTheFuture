shader_type canvas_item;
// D3 - VHS / dead-channel glitch. Drive `amount` from 0 (clean) to 1 (full tear) and
// change `seed_t` every frame of a burst so the torn slices keep reshuffling.
// Reusable: the same shader can go on B's WordPopup from level 3.

uniform float amount : hint_range(0.0, 1.0) = 0.0;
uniform float seed_t = 0.0;
uniform float slices = 22.0;

float rand(float x) {
	return fract(sin(x * 1273.37) * 43758.5453);
}

void fragment() {
	vec2 uv = UV;

	// Shove a few horizontal bands sideways; step() keeps most of them untouched.
	float band = floor(uv.y * slices);
	float r = rand(band + floor(seed_t * 37.0));
	float torn = step(0.62, r);
	uv.x = clamp(uv.x + (r - 0.5) * 0.18 * amount * torn, 0.0, 1.0);

	// Chromatic split: red and blue drift apart as the glitch ramps up.
	float ca = 0.010 * amount;
	vec2 ruv = vec2(clamp(uv.x - ca, 0.0, 1.0), uv.y);
	vec2 buv = vec2(clamp(uv.x + ca, 0.0, 1.0), uv.y);
	vec4 mid = texture(TEXTURE, uv);
	COLOR = vec4(texture(TEXTURE, ruv).r, mid.g, texture(TEXTURE, buv).b, mid.a);

	// Thin dark scanline sweeping down during the burst.
	float line = smoothstep(0.03, 0.0, abs(fract(uv.y - seed_t * 0.9) - 0.5));
	COLOR.rgb -= line * 0.35 * amount;
}
