extends VNEngineCharacterLayer
## Local extension: native show/move/state remain authoritative, upstream stays pinned.
var layout_tweens: Dictionary = {}

func _ready() -> void:
	super._ready()
	resized.connect(_resize_layouts)

func _resize_layouts() -> void:
	for id: String in active_sprites:
		var token := str(active_sprites[id].get_meta("td_layout",""))
		if not token.is_empty(): _apply_layout(id,token)

func show_character(id: String, outfit: String, pose: String, expression: String, shot: String, position_str: String, transition: String) -> void:
	var token := position_str
	if token.is_empty() and active_sprites.has(id): token = str(active_sprites[id].get_meta("td_layout", ""))
	var layout := TDVNLayout.parse(token)
	if token.begins_with("td:") and layout.is_empty():
		push_warning("Invalid TD VN layout: " + token); return
	if layout.is_empty():
		_clear_layout(id)
		if active_sprites.has(id) and not str(active_sprites[id].get_meta("td_layout", "")).is_empty(): _legacy_box(id)
		super.show_character(id,outfit,pose,expression,shot,position_str,transition)
		if active_sprites.has(id): active_sprites[id].set_meta("td_layout", "")
		return
	# Empty position avoids the upstream automatic 0.4s move fighting the authored pose.
	super.show_character(id,outfit,pose,expression,shot,"",transition)
	_apply_layout(id,token)

func move_character(id: String, position_str: String, duration: float) -> void:
	var layout := TDVNLayout.parse(position_str)
	if position_str.begins_with("td:") and layout.is_empty():
		push_warning("Invalid TD VN layout: " + position_str); return
	if layout.is_empty():
		_clear_layout(id)
		if active_sprites.has(id):
			active_sprites[id].set_meta("td_layout", "")
			_legacy_box(id)
		super.move_character(id,position_str,duration)
		return
	if not active_sprites.has(id): return
	var before: Rect2 = active_sprites[id].get_rect()
	_apply_layout(id,position_str)
	var actor: Control = active_sprites[id]
	var after := actor.get_rect()
	if duration > 0 and not runner.is_skip:
		actor.position = before.position; actor.size = before.size
		var tween := create_tween().set_parallel(true)
		tween.tween_property(actor,"position",after.position,duration)
		tween.tween_property(actor,"size",after.size,duration)
		layout_tweens[id] = tween

func _on_dialog_started(node: VNEngineStoryNode) -> void:
	if active_sprites.has(node.speaker_id.to_lower()):
		super._on_dialog_started(node)
		return
	# A narrator or an offscreen voice has no foreground portrait.
	for actor: VNEngineCharacterSprite in active_sprites.values():
		if node.speaker_id.is_empty():
			actor.focus()
			actor.z_index = 0
		else:
			actor.unfocus()

func hide_character(id: String, transition: String) -> void:
	_clear_layout(id)
	var actor: VNEngineCharacterSprite = active_sprites.get(id.to_lower())
	if actor != null:
		actor.z_index = 0
	super.hide_character(id,transition)

func _clear_layout(id: String) -> void:
	if layout_tweens.has(id):
		var tween: Tween = layout_tweens[id]
		if tween != null and tween.is_valid(): tween.kill()
		layout_tweens.erase(id)

func _legacy_box(id: String) -> void:
	var actor: Control = active_sprites[id]
	var center := actor.get_rect().get_center().x / maxf(size.x,1)
	var entry := cast.get_entry(id)
	var cast_scale := entry.sprite_scale if entry != null else 1.0
	actor.anchor_left = center; actor.anchor_right = center
	actor.anchor_top = 1; actor.anchor_bottom = 1
	actor.offset_left = -380.0 * cast_scale; actor.offset_right = 380.0 * cast_scale
	actor.offset_top = -720; actor.offset_bottom = -115

func _apply_layout(id: String, token: String) -> void:
	if not active_sprites.has(id): return
	_clear_layout(id)
	var actor: VNEngineCharacterSprite = active_sprites[id]
	if actor._move_tween != null and actor._move_tween.is_valid(): actor._move_tween.kill()
	var entry := cast.get_entry(id)
	var area := size if size.x > 0 and size.y > 0 else TDVNLayout.DESIGN
	var bounds := TDVNLayout.rect(token,entry.sprite_scale if entry != null else 1.0,area)
	actor.set_anchors_preset(Control.PRESET_TOP_LEFT)
	actor.position = bounds.position; actor.size = bounds.size
	actor.set_meta("td_layout",token)
