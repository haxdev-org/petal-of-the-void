class_name PixelArt
extends RefCounted
## Placeholder pixel sprites drawn from text grids, so the skeleton runs with
## no image files. Replace with real sprite sheets from art/ as they arrive:
## `texture(id)` is the only place scenes ask for sprite textures.

const BAIHUA_PALETTE := {
	"h": Color("e8c872"), "H": Color("b8954a"), "s": Color("f4e4d8"), "e": Color("2a1e2e"),
	"b": Color("233268"), "B": Color("151d42"), "w": Color("f2f0ea"), "g": Color("9aa0a8"),
	"k": Color("2c3e78"), "v": Color("b89bff"),
}
const WOLF_PALETTE := {
	"f": Color("5a5a64"), "F": Color("34343e"), "a": Color("ffb030"), "t": Color("e8e0d0"),
	"g": Color("8cff50"), "n": Color("121212"),
}
const WOLF_DEMON_PALETTE := {
	"f": Color("3a2226"), "F": Color("1c1014"), "a": Color("ff3a2a"), "t": Color("e8e0d0"),
	"g": Color("ff3a2a"), "n": Color("050505"),
}
const BEAR_PALETTE := {
	"b": Color("6b4a33"), "B": Color("40291c"), "q": Color("d8c8a0"), "r": Color("ff4030"),
	"n": Color("121212"),
}

const BAIHUA := [
	"......HhhH......",
	".....HhhhhH.....",
	"....HhhhhhhH....",
	"....hhsssshh....",
	"....hsessesh....",
	"....hssssssh....",
	"...HhhssssshH...",
	"...HhbgggbbH....",
	"...hbbbgbbbbh...",
	"..hbbbbgbbbbbh..",
	"..hbbwwwwwwbbh..",
	"..wbbwwvwwwbbw..",
	"..wbbbbbbbbbbw..",
	"..wBbbbbbbbbBw..",
	"...BbbbbbbbbB...",
	"...BbbbbbbbbB...",
	"...BbbbbbbbbB...",
	"..BbbbbbbbbbbB..",
	"..BbbbbbbbbbbB..",
	"..BwbwbbbwbwbB..",
	"..BwwbwbwbwwbB..",
	"....kkk..kkk....",
	"....kkk..kkk....",
	"...kkkk..kkkk...",
]
const WOLF := [
	"...F....................",
	"..FfF...................",
	".Fffff..................",
	"Ffaffff......FFFFFFF....",
	"nfffffff..FFfffffffffF..",
	".ttfffffFFfffffffffffffF",
	"..g.ffffffffffffffffffF.",
	"....ffffffffffffffffF...",
	".....fffffffffffffff....",
	".....ff.ff.....ff.ff....",
	".....ff.ff.....ff.ff....",
	".....FF.FF.....FF.FF....",
]
const QUILL_BEAR := [
	"..........q..q..q.......",
	"........q.qq.qq.qq.q....",
	".......qqBBBBBBBBBqq....",
	"..BB..qBbbbbbbbbbbBq....",
	".BbbB.Bbbbbbbbbbbbbbq...",
	"BbrbbBbbbbbbbbbbbbbbB...",
	"nbbbbbbbbbbbbbbbbbbbbB..",
	".Bbbbbbbbbbbbbbbbbbbbb..",
	"..BBbbbbbbbbbbbbbbbbbB..",
	"....bbbbbbbbbbbbbbbbbB..",
	"....bbbbbbbbbbbbbbbbbB..",
	"....bbbb.......bbbbbB...",
	"....bbbb.......bbbbB....",
	"....BBBB.......BBBB.....",
]

static var _cache: Dictionary = {}


static func texture(id: StringName) -> Texture2D:
	if _cache.has(id):
		return _cache[id]
	var tex: Texture2D
	match id:
		&"baihua": tex = from_grid(BAIHUA, BAIHUA_PALETTE)
		&"wolf": tex = from_grid(WOLF, WOLF_PALETTE)
		&"wolf_demon": tex = from_grid(WOLF, WOLF_DEMON_PALETTE)
		&"quill_bear": tex = from_grid(QUILL_BEAR, BEAR_PALETTE)
		&"soft_circle": tex = radial(32, Color.WHITE)
		&"petal": tex = petal()
		_:
			push_warning("Unknown sprite id %s" % id)
			tex = radial(16, Color.MAGENTA)
	_cache[id] = tex
	return tex


static func from_grid(rows: Array, palette: Dictionary) -> ImageTexture:
	var width := 0
	for row: String in rows:
		width = maxi(width, row.length())
	var img := Image.create_empty(width, rows.size(), false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in rows.size():
		var row: String = rows[y]
		for x in row.length():
			var ch := row[x]
			if palette.has(ch):
				img.set_pixel(x, y, palette[ch])
	return ImageTexture.create_from_image(img)


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
