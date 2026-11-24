shader_type spatial;
// Inverted-hull ink line. A view-space depth bias plus a close-range
// cutoff keep overlapping TripoSR sheets from poking black triangles
// in close-up; silhouettes at explore distance still read.
// (canvas_item hint_depth_texture is not supported in this renderer.)
render_mode cull_front, unshaded, shadows_disabled, depth_draw_opaque;

uniform vec4 outline_color : source_color = vec4(0.04, 0.035, 0.05, 1.0);
uniform float grow : hint_range(0.0, 0.04) = 0.005;
uniform float dist_scale : hint_range(0.0, 0.01) = 0.0007;
uniform float depth_bias : hint_range(0.0, 0.08) = 0.06;
uniform float min_distance : hint_range(0.0, 12.0) = 6.0;

varying float view_dist;

void vertex() {
	view_dist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
	VERTEX += NORMAL * (grow + view_dist * dist_scale);
	vec4 view = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	// View space looks down -Z; more negative Z is farther from the camera.
	view.z -= depth_bias;
	POSITION = PROJECTION_MATRIX * view;
}

void fragment() {
	if (view_dist < min_distance) {
		discard;
	}
	ALBEDO = outline_color.rgb;
	ALPHA = outline_color.a;
}
