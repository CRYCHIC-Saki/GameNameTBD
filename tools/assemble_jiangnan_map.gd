extends SceneTree
## Authoring utility. The saved scene opens as ordinary TileMapLayers and sprites.

const SCENE_PATH := "res://src/town/jiangnan_map.tscn"
const TILESET_PATH := "res://src/town/jiangnan_map_tileset.tres"
const LAYERS := ["Water", "Land", "Woodlands", "Shore", "GroundDetails", "ContactShadows",
	"Streets", "Squares", "QuayWall", "Wharf", "BridgeDeck", "SurfaceDetails"]

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		printerr("Pass the layout JSON file after --")
		quit(1)
		return
	var input: Variant = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	if not input is Dictionary or not input.has("layers"):
		printerr("Invalid tile assembly data")
		quit(1)
		return
	quit(_assemble(input))

func _assemble(input: Dictionary) -> int:
	var tile_size := int(input.tile_pixels)
	var variants := int(input.variants)
	var tile_atlas := TileSetAtlasSource.new()
	tile_atlas.texture = load("res://assets/town/jiangnan-map-tiles-v3.png")
	tile_atlas.texture_region_size = Vector2i(tile_size,tile_size)
	if tile_atlas.texture == null: return 1

	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i.ONE * tile_size
	tile_set.add_custom_data_layer()
	tile_set.set_custom_data_layer_name(0, "corner_mask")
	tile_set.set_custom_data_layer_type(0, TYPE_INT)
	tile_set.add_source(tile_atlas,0)
	var paving_atlas := TileSetAtlasSource.new()
	paving_atlas.texture = load("res://assets/town/jiangnan-map-paving-v1.png")
	paving_atlas.texture_region_size = tile_atlas.texture_region_size
	if paving_atlas.texture == null: return 1
	tile_set.add_source(paving_atlas,1)
	var frontage_atlas := TileSetAtlasSource.new()
	frontage_atlas.texture = load("res://assets/town/jiangnan-map-frontages-v1.png")
	frontage_atlas.texture_region_size = tile_atlas.texture_region_size
	if frontage_atlas.texture == null: return 1
	tile_set.add_source(frontage_atlas,2)
	var sources: Array[TileSetAtlasSource] = [tile_atlas,paving_atlas,frontage_atlas]
	for material: int in tile_atlas.texture.get_height() / (variants * tile_size):
		for y: int in variants:
			for x: int in variants:
				_assign_tile(tile_atlas,Vector2i(14*variants+x,material*variants+y),15)

	var map := Node2D.new()
	map.name = "JiangnanMap"
	map.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	map.y_sort_enabled = true
	var ground_material := ShaderMaterial.new()
	ground_material.shader = load("res://src/town/jiangnan_ground_light.gdshader")
	var tile_count := 0
	for i: int in LAYERS.size():
		var key: String = LAYERS[i]
		var layer := TileMapLayer.new()
		layer.name = key
		layer.z_index = i-LAYERS.size()-1
		layer.tile_set = tile_set
		if key in ["Land", "Woodlands", "Squares", "Streets", "GroundDetails"]:
			layer.material = ground_material
		layer.scale = Vector2.ONE * float(input.tile_world) / tile_size
		map.add_child(layer)
		layer.owner = map
		for cell: Array in input.layers[key]:
			var coords := Vector2i(cell[2],cell[3])
			var source := int(cell[4]) if cell.size() > 4 else 0
			var mask := int(cell[5]) if source != 0 else 1+coords.x/variants
			_assign_tile(sources[source],coords,mask)
			layer.set_cell(Vector2i(cell[0],cell[1]),source,coords)
			tile_count += 1

	var props := Node2D.new()
	props.name = "Props"
	props.y_sort_enabled = true
	map.add_child(props)
	props.owner = map
	var sprite_sheet := load("res://assets/town/jiangnan-map-props-v2.png") as Texture2D
	var bridge_sheet := load("res://assets/town/jiangnan-map-arches-v1.png") as Texture2D
	if sprite_sheet == null or bridge_sheet == null:
		map.free()
		return 1
	var textures := {}
	for id: String in input.prop_regions:
		var art := AtlasTexture.new()
		art.atlas = sprite_sheet
		art.region = _rect(input.prop_regions[id])
		art.filter_clip = true
		textures[id] = art
	for part: Dictionary in input.props:
		_add_prop(part,textures[part.sprite],textures.shadow,props,map,float(input.source_scale))
	var sunlight := Node2D.new()
	sunlight.set_script(preload("res://src/town/jiangnan_sun_shadows.gd"))
	_attach(map, sunlight, map, "SunShadows", -2)
	var unit := float(input.source_scale)
	_add_waterfront(map, input, bridge_sheet, unit)

	var atmosphere := preload("res://src/town/outdoor_atmosphere.gd").new()
	_attach(map, atmosphere, map, "Atmosphere", 2)

	var result := ResourceSaver.save(tile_set,TILESET_PATH)
	if result == OK:
		tile_set.take_over_path(TILESET_PATH)
		var scene := PackedScene.new()
		result = scene.pack(map)
		if result == OK: result = ResourceSaver.save(scene,SCENE_PATH)
	print("JIANGNAN_ASSEMBLY cells=",tile_count," sprites=",props.get_child_count()," status=",result)
	map.free()
	return 0 if result == OK else 1

func _assign_tile(source: TileSetAtlasSource, coords: Vector2i, mask: int) -> void:
	if source.has_tile(coords): return
	source.create_tile(coords)
	source.get_tile_data(coords,0).set_custom_data("corner_mask",mask)

func _rect(values: Array) -> Rect2:
	return Rect2(float(values[0]),float(values[1]),float(values[2]),float(values[3]))

func _add_prop(part: Dictionary, art: AtlasTexture, shadow: AtlasTexture, props: Node2D, owner_root: Node2D, unit: float) -> void:
	var sprite := Sprite2D.new()
	sprite.name = part.id.replace("-","_")
	sprite.texture = art
	sprite.centered = false
	var target := _rect(part.rect)
	var foot := Vector2(part.foot[0],part.foot[1])
	var span := target.size.x
	if target.size.y > 0:
		span = minf(span,target.size.y * art.get_size().aspect() * 1.28)
	var multiplier := span / art.get_width()
	sprite.position = foot * unit
	sprite.scale = Vector2.ONE * multiplier * unit
	sprite.offset = Vector2((target.get_center().x-foot.x)/multiplier-art.get_width()*.5,
		(target.end.y-foot.y)/multiplier-art.get_height())
	if part.id.begins_with("grove-"):
		var tint := .74 + float(str(part.id).hash()%24)*.01
		sprite.self_modulate = Color(tint,tint,.96*tint)
	sprite.set_meta("scenic_id",part.id)
	sprite.set_meta("scenic_layer",part.layer)
	if part.has("service"): sprite.set_meta("service",part.service)
	if part.get("grass_house",false): sprite.set_meta("grass_house",true)
	if not part.bases.is_empty():
		var footprints: Array[Rect2] = []
		for row: Array in part.bases:
			var box := _rect(row)
			footprints.append(Rect2((box.position-foot)/multiplier,box.size/multiplier))
		sprite.set_meta("footprints",footprints)
	if part.get("enclosed",false): sprite.set_meta("enclosed",true)
	if part.has("walking_feet"):
		var contacts: Array[Rect2] = []
		for row: Array in part.walking_feet:
			var zone := _rect(row)
			contacts.append(Rect2((zone.position-foot)/multiplier,zone.size/multiplier))
		sprite.set_meta("walking_feet",contacts)
	props.add_child(sprite)
	sprite.owner = owner_root
	if not part.get("grass_house",false) and target.size.x >= 25 and (not part.bases.is_empty() or part.id.begins_with("grove-")):
		var shade := Sprite2D.new()
		shade.name = "GroundShadow"
		shade.texture = shadow
		shade.position = Vector2((target.get_center().x-foot.x+span*.08)/multiplier,(target.end.y-foot.y-2.0)/multiplier)
		shade.scale = Vector2(span*.89,span*.26)/(shadow.get_size()*multiplier)
		shade.z_index = -1
		sprite.add_child(shade)
		shade.owner = owner_root

func _attach(parent: Node2D, node: Node2D, map: Node2D, id: String, depth: int) -> void:
	node.name = id
	node.z_index = depth
	parent.add_child(node, true)
	node.owner = map

func _fill(parent: Node2D, map: Node2D, id: String, points: PackedVector2Array, tint: Color, depth := 0) -> void:
	var face := Polygon2D.new()
	face.polygon = points
	face.color = tint
	_attach(parent, face, map, id, depth)

func _stroke(parent: Node2D, map: Node2D, points: PackedVector2Array, tint: Color, width: float) -> void:
	var line := Line2D.new()
	line.points = points
	line.width = width
	line.default_color = tint
	line.joint_mode = Line2D.LINE_JOINT_BEVEL
	_attach(parent, line, map, "Trim", 0)

func _points(values: Array, unit: float) -> PackedVector2Array:
	var output := PackedVector2Array()
	for item: Array in values:
		output.append(Vector2(item[0], item[1]) * unit)
	return output

func _add_waterfront(map: Node2D, input: Dictionary, bridge_sheet: Texture2D, unit: float) -> void:
	var waterfront := Node2D.new()
	_attach(map, waterfront, map, "Waterfront", 0)
	for id: String in input.bridge_art:
		var bridge := Node2D.new()
		_attach(waterfront, bridge, map, id, 0)
		for label: String in ["ArchStonework", "BackRail", "FrontRail"]:
			var part: Dictionary = input.bridge_art[id][label]
			var texture := AtlasTexture.new()
			texture.atlas = bridge_sheet
			texture.region = _rect(part.region)
			texture.filter_clip = true
			var sprite := Sprite2D.new()
			sprite.texture = texture
			sprite.centered = false
			sprite.position = Vector2(part.origin[0],part.origin[1]) * unit
			sprite.scale = Vector2.ONE * unit / float(input.bridge_art_scale)
			_attach(bridge, sprite, map, label, 1 if label == "FrontRail" else -1)
	for id: String in input.timber:
		var pier := Node2D.new()
		_attach(waterfront, pier, map, id, 0)
		var outline := _points(input.timber[id], unit)
		# Run curb and pilings along the exposed face. Keep the shore end open.
		var front := outline.slice(1) if id == "harbor_pier" else outline.slice(5, 11)
		var fascia := front.duplicate()
		for i: int in range(front.size()-1,-1,-1):
			fascia.append(front[i]+Vector2.DOWN*unit*4.0)
		_fill(pier, map, "TimberFace", fascia, Color("#584536"), -1)
		var piles := Node2D.new()
		_attach(pier,piles,map,"Piles",-1)
		for i: int in range(0,front.size(),2):
			var top := front[i]
			var foot := top+Vector2.DOWN*unit*11.0
			_stroke(piles,map,PackedVector2Array([top,foot]),Color("#4b3b29"),unit*4)
			_stroke(piles,map,PackedVector2Array([top-Vector2.RIGHT*unit,foot-Vector2.RIGHT*unit]),Color("#8b6c45"),unit*1.3)
		_timber_rail(pier, map, front, unit)

func _timber_rail(parent: Node2D, map: Node2D, edge: PackedVector2Array, unit: float) -> void:
	var rail := Node2D.new()
	_attach(parent, rail, map, "FrontRail", 1)
	var height := unit * 6.0
	var top := PackedVector2Array()
	var lower := PackedVector2Array()
	for foot: Vector2 in edge:
		top.append(foot - Vector2.DOWN*height)
		lower.append(foot - Vector2.DOWN*height*.35)
	var shadow := Color("#503d2c")
	var middle := Color("#886343")
	var light := Color("#cfad73")
	_stroke(rail, map, lower, shadow, unit*1.65)
	_stroke(rail, map, top, shadow, unit*2.4)
	_stroke(rail, map, top, middle, unit*1.32)
	for i: int in edge.size():
		var foot := edge[i]
		var bottom := foot+Vector2.DOWN*unit*4.5
		var head := top[i]-Vector2.DOWN*unit*1.2
		_stroke(rail, map, PackedVector2Array([bottom, head]), shadow, unit*3.4)
		_stroke(rail, map, PackedVector2Array([bottom-Vector2.DOWN*unit, head]), middle, unit*2.2)
		_stroke(rail, map, PackedVector2Array([head-Vector2.RIGHT*unit*.8, head+Vector2.RIGHT*unit]), light, unit)
