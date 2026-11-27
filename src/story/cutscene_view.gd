class_name TDCutsceneView
extends Control
## Legacy API retained for old previews; production stories use native VN pages.
## No AnimationPlayer, camera motion, timed Foley, walking or scene instantiation.
var shot: String = ""
var elapsed: float = 0.0
var duration: float = 1.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	clip_contents = true

func show_shot(id: String, seconds: float, span: float, _silent_seek: bool = false) -> void:
	shot = id; elapsed = seconds; duration = span
	visible = not id.is_empty()
	queue_redraw()

func stop_audio() -> void:
	pass

func set_audio_paused(_value: bool) -> void:
	pass

func _draw() -> void:
	if shot.is_empty(): return
	var id := str(TDVNPresentation.CG_BACKGROUNDS.get(shot, "restaurant"))
	var texture: Texture2D = load("res://content/story/vn/backgrounds/%s.tres" % id)
	draw_rect(Rect2(Vector2.ZERO, size), Color.BLACK)
	draw_texture_rect(texture, TDStoryArt.fit(texture, Rect2(Vector2.ZERO, size)), false)
