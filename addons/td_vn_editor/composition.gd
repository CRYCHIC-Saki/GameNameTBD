@tool
extends Control
const Document := preload("res://addons/td_vn_editor/document.gd")
signal actor_selected(who: String)
signal actor_moved(who: String, token: String)
var state: Dictionary = {}
var textures: Dictionary = {}
var thumbnail: bool = false
var editable: bool = false
var selected_actor: String = ""
var dragging: bool = false
var drag_start := Vector2.ZERO
var drag_token: String = ""
var drag_bounds := Rect2()

func assign_state(value: Dictionary) -> void:
	cancel_drag()
	state = value.duplicate(true)
	if not state.get("actors",{}).has(selected_actor): selected_actor = ""
	queue_redraw()

func canvas_transform() -> Transform2D:
	var factor := minf(size.x/1280.0,size.y/800.0)
	return Transform2D(0,Vector2.ONE*factor,0,(size-TDVNLayout.DESIGN*factor)*.5)

func actor_bounds(who: String) -> Rect2:
	return TDVNLayout.rect(state.actors[who].get("position","center"),Document.cast_scale(who))

func actor_texture(who: String) -> Texture2D:
	var p: Dictionary = state.actors[who]
	var asset := Document.portrait_path(who,p.get("expression","calm"),p.get("outfit","base"),p.get("pose","base"),p.get("shot","mid"))
	return texture_at(asset) if ResourceLoader.exists(asset) else null

func actor_order() -> Array:
	var result: Array = state.get("actors",{}).keys()
	var speaker: String = state.get("speaker","")
	if result.has(speaker): result.erase(speaker); result.append(speaker)
	return result

func _gui_input(event: InputEvent) -> void:
	if not editable or thumbnail: return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT: cancel_drag(); accept_event(); return
		if event.button_index != MOUSE_BUTTON_LEFT: return
		var point: Vector2 = canvas_transform().affine_inverse()*event.position
		if event.pressed:
			grab_focus()
			var order := actor_order(); order.reverse()
			selected_actor = ""
			for who: String in order:
				var texture := actor_texture(who)
				if texture != null and TDVNLayout.fit(texture,actor_bounds(who)).has_point(point): selected_actor = who; break
			actor_selected.emit(selected_actor)
			if not selected_actor.is_empty():
				dragging = true; drag_start = point
				drag_token = str(state.actors[selected_actor].position); drag_bounds = actor_bounds(selected_actor)
		elif dragging:
			dragging = false
			var token: String = state.actors[selected_actor].position
			if token != drag_token: actor_moved.emit(selected_actor,token)
		queue_redraw(); accept_event()
	elif event is InputEventMouseMotion and dragging:
		var point: Vector2 = canvas_transform().affine_inverse()*event.position
		var delta: Vector2 = point-drag_start
		var layout := TDVNLayout.parse(drag_token)
		var factor := float(layout.get("scale",1.0))
		var bounds := drag_bounds
		bounds.position += delta
		# Keep the authored box on the slide. Position is independent of editor zoom.
		bounds.position.x = clampf(bounds.position.x,0,maxf(0,1280-bounds.size.x))
		bounds.position.y = clampf(bounds.position.y,0,maxf(0,800-bounds.size.y))
		state.actors[selected_actor].position = TDVNLayout.encode(bounds.get_center().x/1280,bounds.end.y/800,factor)
		queue_redraw(); accept_event()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		cancel_drag(); accept_event()

func cancel_drag() -> void:
	if dragging and state.get("actors",{}).has(selected_actor): state.actors[selected_actor].position = drag_token
	dragging = false; queue_redraw()

func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT,NOTIFICATION_VISIBILITY_CHANGED,NOTIFICATION_RESIZED]: cancel_drag()

func texture_at(path: String) -> Texture2D:
	if not textures.has(path): textures[path] = load(path)
	return textures[path]

func _ready() -> void:
	custom_minimum_size = Vector2.ZERO if thumbnail else Vector2(340, 225)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_IGNORE if thumbnail else Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	clip_contents = true
	resized.connect(queue_redraw)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("161e29"))
	draw_set_transform_matrix(canvas_transform())
	var bg_path := Document.BG_ROOT + str(state.get("background", "")) + ".tres"
	if ResourceLoader.exists(bg_path): draw_texture_rect(texture_at(bg_path), Rect2(0,0,1280,800), false)
	for who: String in actor_order():
		var texture := actor_texture(who)
		if texture == null: continue
		var bounds := TDVNLayout.fit(texture,actor_bounds(who))
		var tint := Color.WHITE if state.get("speaker","") in [who, ""] else Color(0.55,0.55,0.6)
		draw_texture_rect(texture,bounds,false,tint)
		if not thumbnail and who == selected_actor:
			draw_rect(bounds.grow(4),Color("5de4de"),false,3)
	draw_rect(Rect2(30,620,1220,155),Color(0.10,0.14,0.20,0.94))
	var font := get_theme_default_font()
	var names := Document.cast_names()
	draw_string(font,Vector2(60,657), str(names.get(state.get("speaker",""),"旁白")),HORIZONTAL_ALIGNMENT_LEFT,1150,26,Color("eac990"))
	draw_multiline_string(font,Vector2(60,703),str(state.get("text", "选择步骤，在右侧编辑。")),HORIZONTAL_ALIGNMENT_LEFT,1150,25,3,Color("eeeeeb"))
	if not str(state.get("cg", "")).is_empty():
		draw_rect(Rect2(0,0,1280,80),Color(0,0,0,.8))
		draw_string(font,Vector2(35,52),"CG · " + str(state.cg) + "（点击试玩播放动画）",HORIZONTAL_ALIGNMENT_LEFT,1200,29)
