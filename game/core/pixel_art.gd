class_name PixelArt
extends RefCounted
## Tiny textures generated in code (petal particle). Character and scenery
## art lives in assets/ and is produced by the scripts in tools/.

static var _cache: Dictionary = {}


static func texture(id: StringName) -> Texture2D:
	if _cache.has(id):
		return _cache[id]
	var tex: Texture2D
	match id:
		&"petal": tex = petal()
		&"soft_circle": tex = radial(32, Color.WHITE)
		_:
			push_warning("Unknown sprite id %s" % id)
			tex = radial(16, Color.MAGENTA)
	_cache[id] = tex
	return tex


static func radial(size: int, color: Color) -> ImageTexture:
	var img := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	var c := (size - 1) / 2.0
	for y in size:
		for x in size:
			var d := Vector2(x - c, y - c).length() / c
			var a := clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(color, a * a))
	return ImageTexture.create_from_image(img)


static func petal() -> ImageTexture:
	var img := Image.create_empty(16, 16, false, Image.FORMAT_RGBA8)
	for y in 16:
		for x in 16:
			# Teardrop: an ellipse narrowing toward the top.
			var u := (x - 7.5) / 7.5
			var v := (y - 7.5) / 7.5
			var width := 0.35 + 0.35 * (v + 1.0) * 0.5
			var inside := (u * u) / (width * width) + v * v
			if inside <= 1.0:
				img.set_pixel(x, y, Color(1, 1, 1, clampf((1.0 - inside) * 3.0, 0.0, 1.0)))
			else:
				img.set_pixel(x, y, Color(1, 1, 1, 0))
	return ImageTexture.create_from_image(img)
