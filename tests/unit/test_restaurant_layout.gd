extends GutTest

var catalog: TDRestaurantCatalog
var layout: TDRestaurantLayout

func before_each() -> void:
	catalog = TDRestaurantCatalog.new()
	var loaded := catalog.load_file()
	assert_true(loaded.ok, loaded.message)
	layout = catalog.default_layout()
	assert_not_null(layout)

func test_default_room_has_every_zone_fixture_and_hotpot_surface() -> void:
	var kinds: Dictionary = {}
	for item: Variant in layout.pieces():
		var piece: Dictionary = item
		kinds[piece["kind"]] = true
		assert_eq(String(piece["style_id"]), "chinese_low")
	for kind: String in catalog.kinds():
		assert_true(kinds.has(kind), kind)
	var hotpot := layout.piece_by_kind("hotpot_table")
	assert_eq(String(hotpot["surface"]), "induction")
	assert_eq(String(hotpot["seat_use"]), "dining")
	assert_false(layout.staff_hired("greeter"))
	assert_false(layout.staff_hired("cashier"))
	assert_eq(layout.interact_code(String(layout.piece_by_kind("welcome_desk")["id"])), "NEED_GREETER")
	assert_eq(layout.interact_code(String(layout.piece_by_kind("cashier")["id"])), "NEED_CASHIER")
	assert_eq(layout.interact_code(String(layout.piece_by_kind("kiosk")["id"])), "READY")
	assert_eq(catalog.furniture("stool")["name"], "凳子")
	var mutated := catalog.furniture("stool")
	mutated["name"] = "changed"
	assert_eq(String(catalog.furniture("stool")["name"]), "凳子")

func test_overlap_and_wrong_zone_leave_the_layout_unchanged() -> void:
	var before := layout.to_dict()
	var overlap := layout.place("stool", 6, 6, 0)
	assert_eq(overlap.code, "OVERLAP")
	var wrong := layout.place("stool", 3, 7, 0)
	assert_eq(wrong.code, "WRONG_ZONE")
	assert_eq(layout.place("missing", 11, 6, 0).code, "UNKNOWN_KIND")
	assert_eq(layout.to_dict(), before)
	var desk := layout.piece_by_kind("welcome_desk")
	assert_eq(layout.paint(int(desk["x"]), int(desk["y"]), ".").code, "OCCUPIED")
	assert_eq(layout.paint(1, 1, ".").code, "LAST_ENTRANCE")
	assert_eq(layout.set_staff("chef", true).code, "INVALID_ROLE")
	assert_false(layout.staff_hired("greeter"))

func test_paths_stay_on_movement_cells_and_a_choke_blocks_them() -> void:
	var corridor := layout.path(Vector2i(1, 1), Vector2i(3, 1))
	assert_eq(corridor, [Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1)])
	for cell: Vector2i in corridor:
		assert_eq(layout.cell_zone(cell.x, cell.y), "movement")
	assert_true(layout.paint(2, 1, "#").ok)
	assert_eq(layout.path(Vector2i(1, 1), Vector2i(3, 1)), [])
	var child := layout.piece_by_kind("child_seat")
	var rotated := layout.rotate_piece(String(child["id"]))
	assert_true(rotated.ok, rotated.message)
	var after := layout.piece(String(child["id"]))
	assert_eq(int(after["rotation"]), 90)
	assert_true(layout.is_walkable(int(after["approach_x"]), int(after["approach_y"])))

func test_guests_need_a_greeter_and_take_distinct_reachable_seats() -> void:
	var denied := layout.route_guest([])
	assert_false(bool(denied["ok"]))
	assert_eq(String(denied["code"]), "NEED_GREETER")
	assert_eq((denied["path"] as Array).size(), 0)
	assert_true(layout.set_staff("greeter", true).ok)
	var first := layout.route_guest([])
	assert_true(bool(first["ok"]), String(first["message"]))
	assert_eq(String(layout.piece(String(first["seat_id"]))["seat_use"]), "dining")
	_assert_walk(first["path"])
	assert_true(layout.is_entrance((first["path"] as Array)[0].x, (first["path"] as Array)[0].y))
	var desk := layout.piece_by_kind("welcome_desk")
	assert_true((first["path"] as Array).has(Vector2i(int(desk["approach_x"]), int(desk["approach_y"]))))
	var seat := layout.piece(String(first["seat_id"]))
	assert_eq((first["path"] as Array)[-1], Vector2i(int(seat["approach_x"]), int(seat["approach_y"])))
	var second := layout.route_guest([first["seat_id"]])
	assert_true(bool(second["ok"]), String(second["message"]))
	assert_ne(String(second["seat_id"]), String(first["seat_id"]))

func test_styles_are_copies_and_placeholder_textures_differ() -> void:
	var other := catalog.default_layout()
	assert_true(layout.apply_venue_style("french", "high").ok)
	assert_eq(other.culture, "chinese")
	assert_eq(String(other.piece_by_kind("sofa")["style_id"]), "chinese_low")
	assert_eq(catalog.default_layout().culture, "chinese")
	var one := layout.piece_by_kind("stool")
	assert_true(layout.restyle_piece(String(one["id"]), "japanese", "low").ok)
	assert_eq(String(layout.piece(String(one["id"]))["style_id"]), "japanese_low")
	assert_eq(String(layout.piece_by_kind("sofa")["style_id"]), "french_high")
	var low := TDRestaurantArt.piece_texture("dining_table", "", "chinese", "low", 128, 128)
	var high := TDRestaurantArt.piece_texture("dining_table", "", "french", "high", 128, 128)
	assert_ne(low.get_image().get_pixel(0, 0), high.get_image().get_pixel(0, 0))
	var chinese_floor := TDRestaurantArt.floor_texture(other)
	var french_floor := TDRestaurantArt.floor_texture(layout)
	assert_ne(chinese_floor.get_image().get_pixel(136, 72), french_floor.get_image().get_pixel(136, 72))

func test_save_roundtrip_refuses_to_replace_an_unknown_version() -> void:
	DirAccess.make_dir_recursive_absolute("res://artifacts/test-storage")
	var path := "res://artifacts/test-storage/restaurant-%d.json" % Time.get_ticks_usec()
	var store := TDRestaurantStore.new(path)
	assert_eq(store.load_layout(catalog).code, "NOT_FOUND")
	assert_true(layout.set_staff("cashier", true).ok)
	assert_true(layout.restyle_piece(String(layout.piece_by_kind("screen")["id"]), "french", "high").ok)
	assert_true(store.save_layout(layout).ok)
	var again := TDRestaurantStore.new(path)
	assert_true(again.load_layout(catalog).ok)
	assert_eq(again.loaded_layout.to_dict(), layout.to_dict())
	assert_true(again.loaded_layout.staff_hired("cashier"))
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string('{"schema_version":99}')
	file.close()
	var bytes := FileAccess.get_file_as_bytes(path)
	assert_eq(store.load_layout(catalog).code, "UNSUPPORTED_VERSION")
	assert_eq(store.save_layout(layout).code, "UNSUPPORTED_VERSION")
	assert_eq(FileAccess.get_file_as_bytes(path), bytes)
	var duplicate: Dictionary = layout.to_dict()
	duplicate["pieces"] = (duplicate["pieces"] as Array).duplicate(true)
	var extra: Dictionary = (duplicate["pieces"] as Array)[0]
	extra = extra.duplicate(true)
	extra["id"] = "piece-dup"
	(duplicate["pieces"] as Array).append(extra)
	assert_null(TDRestaurantLayout.import_dict(duplicate, catalog))
	assert_eq(TDRestaurantLayout.import_code, "OVERLAP")

func _assert_walk(cells: Variant) -> void:
	var path: Array = cells
	assert_gt(path.size(), 1)
	for index in path.size():
		var cell: Vector2i = path[index]
		assert_true(layout.is_walkable(cell.x, cell.y))
		if index == 0:
			continue
		var previous: Vector2i = path[index - 1]
		assert_eq(absi(cell.x - previous.x) + absi(cell.y - previous.y), 1)
