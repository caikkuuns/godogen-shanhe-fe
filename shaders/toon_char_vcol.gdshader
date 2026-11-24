shader_type spatial;
// 第四轮：合并后的单 surface 角色材质。
// COLOR.a >= 0.5 的顶点采样 albedo_tex（TripoSR 身体贴图）；
// COLOR.a < 0.5 的顶点直接使用顶点色（袖口/武器/纯色角色）。
// 贴图 alpha < 0.5 直接 discard（alpha scissor），去掉边缘绒毛。
render_mode cull_back, diffuse_toon, specular_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform vec4 albedo_tint : source_color = vec4(1.0);
uniform float self_light : hint_range(0.0, 1.0) = 0.12;
uniform vec3 fill_color : source_color = vec3(0.86, 0.86, 0.88);
// TripoSR 贴图整体偏暗（葛三秤/厉横平均亮度只有 0.08–0.13），
// 不补光会变成黑剪影；按模型给 1.0–1.8 的增益。
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
	float light = self_light;
	if (!is_flat) {
		float lum = dot(c, vec3(0.299, 0.587, 0.114));
		float chroma = max(c.r, max(c.g, c.b)) - min(c.r, min(c.g, c.b));
		bool uv_edge = UV.x < 0.012 || UV.x > 0.988 || UV.y < 0.012 || UV.y > 0.988;
		bool gutter = lum >= 0.18 && lum < 0.62 && chroma < 0.14 && (uv_edge || lum < 0.56);
		if (gutter) {
			c = fill_color;
			light = 0.85;
		}
	}
	ALBEDO = c;
	EMISSION = c * light;
}
