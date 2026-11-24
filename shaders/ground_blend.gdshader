shader_type spatial;
// 第八轮：地面草地/土路双贴图混合（素材来自 wuxia-team/art ground_*_tile.png）。
// 混合系数走顶点色 alpha：world_builder._build_ground 把土路/广场的混合度写入
// COLOR.a，草地/土路各处色调仍由顶点色 rgb 承担（乘 2.2 补回贴图混合的亮度）。
// 顶视无缝 tile，2m 一块；uv 分别缩放让两种贴图密度一致。
render_mode cull_back;

uniform sampler2D grass_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D dirt_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform float uv_scale = 46.0; // 92m 宽的地面 → x 方向 2m/块；z 方向按 66 缩放

void fragment() {
	vec3 grass = texture(grass_tex, UV * vec2(uv_scale, uv_scale * 66.0 / 46.0)).rgb;
	vec3 dirt = texture(dirt_tex, UV * vec2(uv_scale, uv_scale * 66.0 / 46.0) * 0.75).rgb;
	ALBEDO = mix(grass, dirt, COLOR.a) * COLOR.rgb * 2.2;
	ROUGHNESS = 0.97;
	SPECULAR = 0.0;
}
