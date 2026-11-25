class_name TDShiomiArt
extends RefCounted
const SCENE := preload("res://src/town/shiomi_map.tscn")
const WALK_LAYERS := ["Wharf","QuayStone","Streets","WhiteCourts","DryGarden","Meadows","DryRiverbed","ShellBeach"]

static func instance() -> Node2D:
	var scene:=SCENE.instantiate() as Node2D
	scene.position=TDShiomiLayout.world_point(Vector2.ZERO)
	scene.scale=Vector2.ONE*TDTownWorld.CELL/TDShiomiLayout.PIXELS_PER_CELL
	return scene

static func can_stand(scene: Node2D,world: Vector2) -> bool:
	var point:=scene.transform.affine_inverse()*world
	var bridge: Rect2=scene.get_meta("bridge_bounds")
	if bridge.grow(2.0).has_point(point):
		var lane: PackedVector2Array=scene.get_meta("bridge_lane")
		if Geometry2D.is_point_in_polygon(point,lane): return true
		if bridge.has_point(point): return false
	return TDShiomiLayout.foot_clear(point)

static func overview() -> SubViewport:
	var view:=SubViewport.new()
	view.disable_3d=true
	view.transparent_bg=true
	view.size=Vector2i(1460,1460)
	view.render_target_update_mode=SubViewport.UPDATE_ONCE
	var scene:=instance()
	var factor:=float(view.size.x)/(73*TDTownWorld.CELL)
	scene.position*=factor
	scene.scale*=factor
	view.add_child(scene)
	return view
