class_name TDRestaurantArt
extends RefCounted

static var _cache: Dictionary = {}

const PALETTES := {
	"plain_low": {"floor": "#7d8a80", "wood": "#8d7358", "accent": "#d9c7a4", "cloth": "#c46a4a", "metal": "#6e7270"},
	"plain_high": {"floor": "#314640", "wood": "#f0ddb8", "accent": "#ecb36e", "cloth": "#f7f3ea", "metal": "#d5dbd8"},
	"chinese_low": {"floor": "#7a463c", "wood": "#8b5a38", "accent": "#c45448", "cloth": "#a33b32", "metal": "#6b5344"},
	"chinese_high": {"floor": "#4c1c24", "wood": "#e3c072", "accent": "#ff4b3e", "cloth": "#f4d48a", "metal": "#ffe7a8"},
	"japanese_low": {"floor": "#d2c4a8", "wood": "#b08960", "accent": "#3e5160", "cloth": "#8ea0a6", "metal": "#4d463c"},
	"japanese_high": {"floor": "#f4ead4", "wood": "#d29a45", "accent": "#17345c", "cloth": "#fff8ec", "metal": "#ecd8aa"},
	"french_low": {"floor": "#d9d0c2", "wood": "#a67b5d", "accent": "#8d4548", "cloth": "#eadfce", "metal": "#8a847c"},
	"french_high": {"floor": "#f7f3eb", "wood": "#fffaf3", "accent": "#7a1e2b", "cloth": "#f6e2c0", "metal": "#e0b85a"},
	"modern_low": {"floor": "#8d9390", "wood": "#c5beb4", "accent": "#5f6f78", "cloth": "#d5ddd8", "metal": "#9aa3a8"},
	"modern_high": {"floor": "#dfe6e2", "wood": "#f4f1ea", "accent": "#1f3a4d", "cloth": "#ffffff", "metal": "#c5a15a"},
	"life_low": {"floor": "#c4b49a", "wood": "#a98462", "accent": "#6f8f71", "cloth": "#e7d7c3", "metal": "#8c8175"},
	"life_high": {"floor": "#efe4d4", "wood": "#e7c89a", "accent": "#3f6b4e", "cloth": "#fffaf3", "metal": "#d7b56a"},
	"british_low": {"floor": "#6e7c6a", "wood": "#7c5b3a", "accent": "#8c2f2f", "cloth": "#d7c3a3", "metal": "#5c6168"},
	"british_high": {"floor": "#1d2a28", "wood": "#e6d3a1", "accent": "#9e2b2b", "cloth": "#f3efe4", "metal": "#d4af37"},
	"indian_low": {"floor": "#b5652e", "wood": "#8a4b2f", "accent": "#d4a017", "cloth": "#e07a3d", "metal": "#6b4a32"},
	"indian_high": {"floor": "#7a2e12", "wood": "#f0c36a", "accent": "#ffb703", "cloth": "#fff1d6", "metal": "#ffe08a"},
	"nordic_low": {"floor": "#8aa0a8", "wood": "#c8b89a", "accent": "#355c7d", "cloth": "#d5dde0", "metal": "#6d7c84"},
	"nordic_high": {"floor": "#e7eef0", "wood": "#f7f4ee", "accent": "#1d3d5c", "cloth": "#ffffff", "metal": "#b9c6ce"},
	"russian_low": {"floor": "#8d3d3d", "wood": "#6b4226", "accent": "#c4b45a", "cloth": "#d9b4a0", "metal": "#4e5550"},
	"russian_high": {"floor": "#6a1b2a", "wood": "#e6c98a", "accent": "#f2efe9", "cloth": "#f7e1c4", "metal": "#d4af37"},
}

static func floor_texture(layout: TDRestaurantLayout) -> ImageTexture:
	var key := "floor:%s:%s:%d" % [layout.culture, layout.tier, layout.to_dict()["rows"].hash()]
	if _cache.has(key):
		return _cache[key]
	var cell := layout.cell_px
	var image := Image.create(layout.columns * cell, layout.rows * cell, false, Image.FORMAT_RGBA8)
	for y in layout.rows:
		for x in layout.columns:
			var zone := layout.cell_zone(x, y)
			var color := _floor_color(layout.culture, layout.tier, zone, layout.is_entrance(x, y))
			image.fill_rect(Rect2i(x * cell, y * cell, cell, cell), color)
			_pattern(image, Rect2i(x * cell, y * cell, cell, cell), layout.culture, layout.tier)
	var texture := ImageTexture.create_from_image(image)
	_cache[key] = texture
	return texture

static func piece_texture(kind: String, surface: String, culture: String, tier: String, width_px: int, height_px: int) -> ImageTexture:
	var key := "%s:%s:%s:%s:%d:%d" % [kind, surface, culture, tier, width_px, height_px]
	if _cache.has(key):
		return _cache[key]
	var image := Image.create(maxi(width_px, 1), maxi(height_px, 1), false, Image.FORMAT_RGBA8)
	var palette := _palette(culture, tier)
	var wood := Color(palette["wood"])
	var accent := Color(palette["accent"])
	var cloth := Color(palette["cloth"])
	var metal := Color(palette["metal"])
	image.fill(wood)
	image.fill_rect(Rect2i(0, 0, width_px, 3), accent)
	image.fill_rect(Rect2i(0, height_px - 3, width_px, 3), accent)
	image.fill_rect(Rect2i(0, 0, 3, height_px), accent)
	image.fill_rect(Rect2i(width_px - 3, 0, 3, height_px), accent)
	if tier == "high":
		image.fill_rect(Rect2i(6, 6, maxi(width_px - 12, 1), 2), Color(palette["metal"]))
	_icon(image, kind, surface, accent, cloth, metal)
	var texture := ImageTexture.create_from_image(image)
	_cache[key] = texture
	return texture

static func guest_texture() -> ImageTexture:
	if _cache.has("guest"):
		return _cache["guest"]
	var image := Image.create(28, 40, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	image.fill_rect(Rect2i(8, 2, 12, 12), Color("#f2d3b5"))
	image.fill_rect(Rect2i(6, 14, 16, 16), Color("#3f6f8f"))
	image.fill_rect(Rect2i(8, 30, 5, 8), Color("#243038"))
	image.fill_rect(Rect2i(15, 30, 5, 8), Color("#243038"))
	var texture := ImageTexture.create_from_image(image)
	_cache["guest"] = texture
	return texture

static func _floor_color(culture: String, tier: String, zone: String, entrance: bool) -> Color:
	var culture_tint := Color(_palette(culture, tier)["floor"])
	var base := culture_tint
	match zone:
		"facade":
			base = Color("#241c18")
		"movement":
			base = Color("#d7c4a2")
		"reception":
			base = Color("#6f9a80")
		"ordering":
			base = Color("#c6a15a")
		"dining":
			base = Color("#c45b4a")
		_:
			base = culture_tint
	base = base.lerp(culture_tint, 0.42)
	if tier == "high":
		base = base.lightened(0.16)
	if entrance:
		base = base.lerp(Color("#f6e7bf"), 0.55)
	return base

static func _pattern(image: Image, rect: Rect2i, culture: String, tier: String) -> void:
	for y in rect.size.y:
		for x in rect.size.x:
			var mark := false
			match culture:
				"chinese":
					mark = x % 8 == 0 or y % 8 == 0
				"japanese":
					mark = y % 10 == 0
				"french":
					mark = x == 4 or y == 4 or x == rect.size.x - 5 or y == rect.size.y - 5
				_:
					mark = (int(x / 8) + int(y / 8)) % 2 == 0 and (x % 8 == 0 or y % 8 == 0)
			if mark:
				var pixel := Vector2i(rect.position.x + x, rect.position.y + y)
				image.set_pixelv(pixel, image.get_pixelv(pixel).darkened(0.28))
	if tier == "high":
		image.fill_rect(Rect2i(rect.position.x + 2, rect.position.y + 2, rect.size.x - 4, 1), Color("#e7c56a"))

static func _icon(image: Image, kind: String, surface: String, accent: Color, cloth: Color, metal: Color) -> void:
	var size := image.get_size()
	var center := Vector2i(int(size.x / 2), int(size.y / 2))
	match kind:
		"waiting_seat", "stool", "child_seat":
			_disc(image, center, 8 if kind != "child_seat" else 5, cloth)
		"sofa", "booth":
			image.fill_rect(Rect2i(8, 8, int(size.x) - 16, int(size.y) - 16), cloth)
		"dining_table", "hotpot_table":
			image.fill_rect(Rect2i(10, 10, int(size.x) - 20, int(size.y) - 20), cloth.darkened(0.15))
		"screen":
			image.fill_rect(Rect2i(center.x - 2, 6, 4, int(size.y) - 12), accent)
		"kiosk":
			image.fill_rect(Rect2i(8, 8, int(size.x) - 16, int(size.y) - 18), Color("#1c2428"))
		"cashier", "order_counter", "welcome_desk", "storefront":
			image.fill_rect(Rect2i(8, int(size.y / 2), int(size.x) - 16, maxi(int(size.y / 3), 4)), metal)
		_:
			pass
	if surface == "induction":
		_disc(image, center, 10, Color("#d23a32"))
		_disc(image, center, 4, Color("#2a2e30"))

static func _disc(image: Image, center: Vector2i, radius: int, color: Color) -> void:
	for y in range(center.y - radius, center.y + radius + 1):
		for x in range(center.x - radius, center.x + radius + 1):
			if x < 0 or y < 0 or x >= image.get_width() or y >= image.get_height():
				continue
			if Vector2(x - center.x, y - center.y).length() <= radius:
				image.set_pixel(x, y, color)

static func swatch(culture: String, tier: String) -> Dictionary:
	return _palette(culture, tier)

static func zone_color(culture: String, tier: String, zone: String, entrance: bool) -> Color:
	return _floor_color(culture, tier, zone, entrance)

static func _palette(culture: String, tier: String) -> Dictionary:
	var key := "%s_%s" % [culture, tier]
	if PALETTES.has(key):
		return PALETTES[key]
	return PALETTES["plain_low"]
