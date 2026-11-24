shader_type canvas_item;
render_mode blend_mix;

// 轻量后处理：暗角 0.15 + 极轻颗粒 0.015。不采样屏幕纹理，不加重 blur。
uniform float vignette_strength : hint_range(0.0, 0.5) = 0.15;
uniform float grain_strength : hint_range(0.0, 0.05) = 0.015;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void fragment() {
	vec2 uv = UV;
	float d = distance(uv, vec2(0.5));
	float vig = smoothstep(0.34, 0.92, d) * vignette_strength;
	float n = hash(uv * vec2(1920.0, 1080.0) + floor(TIME * 12.0)) - 0.5;
	float grain = n * grain_strength;
	COLOR = vec4(vec3(0.02, 0.025, 0.03) + grain, clamp(vig + abs(grain) * 0.55, 0.0, 0.45));
}
