extends Node2D
## One background character at each selected facade, using current map frontage geometry.
const JIANGNAN := ["diner", "west-courtyard-houses", "east-low-courtyard-homes"]
const VISITS := {
	"tokyo": ["competitor:shop:0", "residences-a", "residences-b"],
	"paris": ["competitor:shop:1", "competitor:shop:2", "residences-a"],
}
const HEIGHT_RATIO := .86
const DOOR_CLEARANCE := 42.0

static func jiangnan_sites(facades: Array) -> Dictionary:
	var sites := {}
	for facade: Dictionary in facades:
		var id: String = facade.get("reference_id", "")
		if id in JIANGNAN:
			var rect: Rect2 = facade.rect
			sites[id] = Vector2(rect.get_center().x, float(facade.sort_y) + 20.0)
	return sites

static func travel_sites(town_id: String, buildings: Array[Dictionary]) -> Dictionary:
	var sites := {}
	var selected: Array = VISITS.get(town_id, [])
	for building: Dictionary in buildings:
		var id: String = building.plot.get("id", "")
		var base: Rect2 = building.base
		if id in selected and base.has_area():
			sites[id] = Vector2(base.get_center().x, base.end.y + 20.0)
	return sites

func refresh(sites: Dictionary, can_stand: Callable, hero_height: float) -> void:
	for child: Node in get_children():
		if not sites.has(child.get_meta("site_id")):
			remove_child(child)
			child.queue_free()
	for id: String in sites:
		var node_name := id.replace(":", "_")
		var actor := get_node_or_null(NodePath(node_name)) as TDStoryArt.TownActor
		if actor == null:
			actor = TDStoryArt.TownActor.new()
			actor.name = node_name
			actor.set_meta("site_id", id)
			add_child(actor)
		var doorway: Vector2 = sites[id]
		actor.set_meta("doorway", doorway)
		var clear_side := func(feet: Vector2) -> bool:
			return absf(feet.x - doorway.x) >= DOOR_CLEARANCE and feet.y >= doorway.y - 4.0 and can_stand.call(feet)
		actor.place("crowd", hero_height * HEIGHT_RATIO, doorway, clear_side)

func face_nearby(point: Vector2) -> void:
	for actor: TDStoryArt.TownActor in get_children():
		actor.face_nearby(point)

func map_locations(origin: Vector2, cell_size: float) -> Dictionary:
	var locations := {}
	for actor: TDStoryArt.TownActor in get_children():
		if actor.visible: locations[actor.get_meta("site_id")]=(actor.position-origin)/cell_size
	return locations

func clear_step(from: Vector2, to: Vector2, spacing: float) -> bool:
	for actor: TDStoryArt.TownActor in get_children():
		if actor.visible and not TDInteractionRange.npc_clear(from,to,actor.position,spacing): return false
	return true

func talk_site(point: Vector2, facing: Vector2i) -> String:
	var site := ""
	var best := INF
	for actor: TDStoryArt.TownActor in get_children():
		if not actor.visible: continue
		var offset := actor.position - point
		var distance := offset.length_squared()
		if distance < best and TDInteractionRange.faces(point, facing, actor.position, 76.0):
			best = distance
			site = str(actor.get_meta("site_id"))
	return site
