shader_type spatial;
// Front pass: same toon look as the StandardMaterial path, but mid-grey
// atlas-gutter fills are replaced with a cloth colour so those triangles
// do not sit on top of the unshaded inside pass.
// 第三轮：保留雾，让 16m 外的 NPC 与场景一起退远，不再像贴纸浮在雾上。
render_mode cull_back, diffuse_toon, specular_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform vec4 albedo_tint : source_color = vec4(1.0);
uniform float self_light : hint_range(0.0, 1.0) = 0.12;
uniform vec3 fill_color : source_color = vec3(0.86, 0.86, 0.88);
// TripoSR 贴图整体偏暗（葛三秤/厉横平均亮度只有 0.08–0.13），
// 不补光会变成黑剪影；按模型给 1.0–1.8 的增益。
uniform float albedo_gain : hint_range(0.5, 3.0) = 1.0;
// 第十轮：gutter 填充总开关。
// gutter 的本意是把 TripoSR atlas 里岛与岛之间的灰底空隙涂成布料色，
// 但它的判定条件（0.18<=lum<0.62 且低饱和）同时会把白袍的褶皱暗部、
// UV 岛边缘的过渡像素一并刷成 0.86 亮灰 + 0.85 自发光 —— 这就是第10轮
// 美术评审判定的 P0「白袍碎三角斑」的直接成因（实测岛内 16.6% 像素命中）。
// 贴图侧已做 UV 岛边缘扩张（gutter 像素被邻岛色填满，见
// docs/round10/贴图修复说明.md），所以沈砚 hero 版可以整体关掉填充；
// 其它未做贴图处理的老模型保持 1.0，行为不变。
uniform float gutter_enabled : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec3 c = texture(albedo_tex, UV).rgb * albedo_tint.rgb * albedo_gain;
	float lum = dot(c, vec3(0.299, 0.587, 0.114));
	float chroma = max(c.r, max(c.g, c.b)) - min(c.r, min(c.g, c.b));
	bool uv_edge = UV.x < 0.012 || UV.x > 0.988 || UV.y < 0.012 || UV.y > 0.988;
	// 第八轮合并（自 grokbot fe）：肤色护栏——高光下淡暖的脸颊/额头像素
	// 过不了旧 gutter 判定里的低饱和条件，被刷成 0.86 灰白（白带横脸）。
	// 暖色或淡暖都算皮肤，永不填充；冷色 trim（蓝腰带/青饰）同样跳过。
	// gutter 放宽（lum<0.88 的内部 speckle）本轮不取，待截图 A/B。
	bool skin = lum > 0.28 && c.r >= c.g - 0.03 && c.r > c.b
		&& (c.r > c.b + 0.018 || (lum > 0.48 && c.r > c.b + 0.006));
	bool trim = c.b > c.r + 0.07 && c.b > c.g + 0.04 && chroma > 0.10;
	bool gutter = gutter_enabled > 0.5 && lum >= 0.18 && lum < 0.62 && chroma < 0.14
		&& !skin && !trim && (uv_edge || lum < 0.56);
	if (gutter) {
		c = fill_color;
		ALBEDO = c;
		EMISSION = c * 0.85;
	} else {
		ALBEDO = c;
		EMISSION = c * self_light;
	}
}
