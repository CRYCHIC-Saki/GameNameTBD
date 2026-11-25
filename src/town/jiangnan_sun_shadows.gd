extends Node2D
## Project each opaque sprite onto the ground from its actual painted base.

var direction := Vector2.ZERO
var strength := 0.0
var _minute := -1
var _casters: Array[Sprite2D] = []

func _ready() -> void:
	var props := get_parent().get_node_or_null("Props")
	if props==null:
		for child: Node in get_parent().get_parent().get_children():
			var caster := child as Sprite2D
			if caster!=null and str(caster.get_meta("art","")) in ["hall","chapel","forge","inn","mill","gable","twins","thatch","shop","market","oak","oak_wide","lime","passenger-station","lamp","carriage","fountain","gate","well","bench","ship"]:
				_casters.append(caster)
		set_day_minute(720.0)
		return
	for child: Node in props.get_children():
		var prop := child as Sprite2D
		if prop == null: continue
		var id := String(prop.get_meta("scenic_id", ""))
		var size := (prop.transform * prop.get_rect()).size
		if size.y < 36 or id.begins_with("covered-boat-") or id == "ferry-junk": continue
		if id.begins_with("detail-") or id.begins_with("bank-detail-"): continue
		if id.begins_with("grove-") and posmod(id.hash(), 3) != 0: continue
		_casters.append(prop)
	set_day_minute(720.0)

func register_caster(sprite: Sprite2D) -> void:
	_casters.append(sprite)
	queue_redraw()

func set_day_minute(value: float) -> void:
	var minute := floori(value)
	if minute == _minute: return
	_minute = minute
	var daylight := clampf((minute - 480.0) / 240.0, 0.0, 1.0)
	var afternoon := smoothstep(720.0, 1110.0, float(minute))
	var west := 1.0 - smoothstep(0.0, 1.0, daylight)
	direction = Vector2(-0.57 * west + 0.69 * afternoon, 0.11 + 0.19 * (west + afternoon))
	strength = (0.23 + 0.11 * (west + afternoon)) * (1.0 - smoothstep(1110.0, 1190.0, float(minute)))
	queue_redraw()

func _draw() -> void:
	if strength <= 0.001: return
	var ink := Color(0.11, 0.16, 0.24, strength)
	for prop: Sprite2D in _casters:
		var bounds := global_transform.affine_inverse() * prop.global_transform * prop.get_rect()
		var foot := Vector2(bounds.get_center().x, bounds.end.y)
		draw_set_transform_matrix(Transform2D(Vector2.LEFT if prop.flip_h else Vector2.RIGHT, -direction, foot))
		var dest := Rect2(Vector2(-bounds.size.x*.5,-bounds.size.y),bounds.size)
		if prop.region_enabled: draw_texture_rect_region(prop.texture,dest,prop.region_rect,ink)
		else: draw_texture_rect(prop.texture,dest,false,ink)
	draw_set_transform_matrix(Transform2D.IDENTITY)

func draw_person(canvas: Node2D, texture: Texture2D, bounds: Rect2, mirrored := false) -> void:
	var foot := Vector2(bounds.get_center().x, bounds.end.y)
	canvas.draw_set_transform(foot, 0, Vector2(1.0, 0.28))
	canvas.draw_circle(Vector2.ZERO, bounds.size.y * 0.10, Color(0.08,0.13,0.19,0.28))
	if strength > 0.001:
		canvas.draw_set_transform_matrix(Transform2D(Vector2.LEFT if mirrored else Vector2.RIGHT, -direction, foot))
		canvas.draw_texture_rect(texture, Rect2(Vector2(-bounds.size.x*0.5,-bounds.size.y), bounds.size), false,
			Color(0.11,0.16,0.24,strength))
	canvas.draw_set_transform_matrix(Transform2D.IDENTITY)
