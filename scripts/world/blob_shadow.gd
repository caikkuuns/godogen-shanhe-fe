class_name BlobShadow
extends RefCounted
## Procedural soft blob shadow (docs/ref-characters-v2 shadow reference).
## Generated in code so the vertical slice does not depend on prebuilt FX files.

static var _cache: Texture2D

static func texture() -> Texture2D:
	if _cache != null:
		return _cache
	var w := 128
	var h := 64
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.0, 0.0, 0.0, 0.0))
	for y in h:
		for x in w:
			# Slight bottom-right bias to match the top-left key light.
			var u := (float(x) - float(w) * 0.53) / (float(w) * 0.5)
			var v := (float(y) - float(h) * 0.55) / (float(h) * 0.5)
			var d := sqrt(u * u + v * v)
			var a := clampf(1.0 - d, 0.0, 1.0)
			a = a * a * 0.55
			img.set_pixel(x, y, Color(0.07, 0.086, 0.118, a))
	_cache = ImageTexture.create_from_image(img)
	return _cache
