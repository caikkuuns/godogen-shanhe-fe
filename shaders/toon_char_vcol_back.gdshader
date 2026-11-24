shader_type spatial;
// 合并 surface 的第二遍（cull front，无光照）：盖住 TripoSR 扫描网格的洞，
// 避免洞后露出灰色背面。纯色顶点直接输出顶点色。
render_mode cull_front, unshaded, shadows_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform vec4 albedo_tint : source_color = vec4(1.0);
uniform vec3 fill_color : source_color = vec3(0.86, 0.86, 0.88);
uniform float albedo_gain : hint_range(0.5, 3.0) = 1.0;

void fragment() {
	vec4 tex = texture(albedo_tex, UV);
	bool is_flat = COLOR.a < 0.5;
	vec3 c = is_flat ? COLOR.rgb : tex.rgb * albedo_gain;
	float alpha = is_flat ? 1.0 : tex.a;
	if (alpha < 0.5) {
		discard;
	}
	c *= albedo_tint.rgb;
	if (!is_flat) {
		float lum = dot(c, vec3(0.299, 0.587, 0.114));
		float chroma = max(c.r, max(c.g, c.b)) - min(c.r, min(c.g, c.b));
		// 皮肤保留贴图；灰白 atlas gutter 变成布料色。
		bool skin = c.r > c.b + 0.04 && c.g > c.b * 0.85 && lum > 0.28;
		if (!skin && lum >= 0.16 && lum < 0.78 && chroma < 0.22) {
			c = fill_color;
		}
	}
	ALBEDO = c;
}
