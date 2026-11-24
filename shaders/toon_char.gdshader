shader_type spatial;
// Second pass for textured characters: draw the inside (cull front) unshaded
// so holes in the TripoSR mesh are covered by cloth colour, not grey lit backs.
// 第八轮合并（自 grokbot fe）：hole_grow 顶点沿法线微膨胀，内层 pass 收小网格洞，
// 防止草地从缺三角处透出；shenyan 的脸不膨胀（toon_model.hole_grow_for 给 0）。
// 保留我们的 albedo_gain（暗模补光）与雾（第三轮纵深决策）——不取它的 fog_disabled。
render_mode cull_front, unshaded, shadows_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform vec4 albedo_tint : source_color = vec4(1.0);
uniform vec3 fill_color : source_color = vec3(0.86, 0.86, 0.88);
uniform float albedo_gain : hint_range(0.5, 3.0) = 1.0;
uniform float hole_grow : hint_range(0.0, 0.03) = 0.006;

void vertex() {
	VERTEX += NORMAL * hole_grow;
}

void fragment() {
	vec3 c = texture(albedo_tex, UV).rgb * albedo_tint.rgb * albedo_gain;
	float lum = dot(c, vec3(0.299, 0.587, 0.114));
	float chroma = max(c.r, max(c.g, c.b)) - min(c.r, min(c.g, c.b));
	// 第八轮合并（自 grokbot fe）：肤色判定细化。暖色或淡暖都算皮肤，
	// 修"额头/脸颊白色碎片带"——高光下的淡暖肤色像素过不了旧的
	// r > b+0.04 严格判定，被刷成了 0.86 灰白 robe fill。
	// trim 冷色保护：蓝腰带/青饰不刷成布色。
	bool skin = lum > 0.28 && c.r >= c.g - 0.03 && c.r > c.b
		&& (c.r > c.b + 0.018 || (lum > 0.48 && c.r > c.b + 0.006));
	bool trim = c.b > c.r + 0.07 && c.b > c.g + 0.04 && chroma > 0.10;
	bool robe_speckle = !skin && !trim && chroma < 0.16 && lum >= 0.12 && lum < 0.92
		&& abs(c.r - c.g) < 0.09 && abs(c.g - c.b) < 0.12
		&& c.r <= c.b + 0.006;
	if (robe_speckle) {
		c = fill_color;
	}
	ALBEDO = c;
}
