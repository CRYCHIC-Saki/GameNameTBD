class_name TDSoundEffects
extends Node
## Shell-owned presentation only. No singleton, simulation mutation or save data.
signal played(event_id: String, source_path: String)
const EVENTS: Dictionary = {
	"ui.hover": [preload("res://assets/audio/sfx/ui/cozy-cafe-sfx/ui-hover.wav"), -22, 120, true],
	"ui.click": [preload("res://assets/audio/sfx/ui/cozy-cafe-sfx/ui-click.wav"), -14, 120, true],
	"ui.confirm": [preload("res://assets/audio/sfx/ui/kenney_interface-sounds/confirmation_001.ogg"), -14, 120, true],
	"ui.back": [preload("res://assets/audio/sfx/ui/cozy-cafe-sfx/ui-back.wav"), -14, 120, true],
	"ui.error": [preload("res://assets/audio/sfx/ui/cozy-cafe-sfx/ui-error.wav"), -14, 120, true],
	"ui.open": [preload("res://assets/audio/sfx/ui/cozy-cafe-sfx/menu-open.wav"), -14, 120, true],
	"ui.close": [preload("res://assets/audio/sfx/ui/cozy-cafe-sfx/menu-close.wav"), -14, 120, true],
	"ui.save_ok": [preload("res://assets/audio/sfx/ui/kenney_interface-sounds/confirmation_002.ogg"), -14, 120, true],
	"restaurant.open": [preload("res://assets/audio/sfx/restaurant/cozy-cafe-sfx/jingle-cafe-open.wav"), -14, 75, true],
	"restaurant.close": [preload("res://assets/audio/sfx/restaurant/cozy-cafe-sfx/jingle-cafe-close.wav"), -14, 75, true],
	"restaurant.order_new": [preload("res://assets/audio/sfx/restaurant/cozy-cafe-sfx/new-order.wav"), -14, 75, false],
	"restaurant.pass_ready": [preload("res://assets/audio/sfx/restaurant/cozy-cafe-sfx/order-ready.wav"), -14, 75, false],
	"restaurant.plate_take": [preload("res://assets/audio/sfx/cooking/cozy-cafe-sfx/plate-place.wav"), -14, 75, false],
	"restaurant.serve": [preload("res://assets/audio/sfx/cooking/cozy-cafe-sfx/serve-dish.wav"), -14, 75, false],
	"restaurant.payment": [preload("res://assets/audio/sfx/restaurant/cozy-cafe-sfx/cash-register.wav"), -14, 75, false],
	"restaurant.tip": [preload("res://assets/audio/sfx/restaurant/cozy-cafe-sfx/tip-jar.wav"), -14, 75, false],
	"restaurant.recipe_unlock": [preload("res://assets/audio/sfx/restaurant/cozy-cafe-sfx/recipe-unlocked.wav"), -14, 75, true],
	"restaurant.unhappy": [preload("res://assets/audio/sfx/restaurant/cozy-cafe-sfx/customer-unhappy.wav"), -14, 75, false],
	"restaurant.day_settle": [preload("res://assets/audio/sfx/restaurant/cozy-cafe-sfx/jingle-day-earnings.wav"), -14, 75, true],
	"cooking.m1_cut_hit": [preload("res://assets/audio/sfx/cooking/kenney_rpg-audio/chop.ogg"), -14, 75, false],
	"cooking.m1_rotate": [preload("res://assets/audio/sfx/ui/kenney_interface-sounds/tick_001.ogg"), -14, 75, false],
	"cooking.m2_ignite": [preload("res://assets/audio/sfx/ui/kenney_interface-sounds/switch_002.ogg"), -14, 75, false],
	"cooking.m3_stir_hit": [preload("res://assets/audio/sfx/cooking/kenney_impact-sounds/impactMetal_light_000.ogg"), -14, 75, false],
	"cooking.m6_start": [preload("res://assets/audio/sfx/ui/kenney_interface-sounds/glass_001.ogg"), -14, 75, false],
	"cooking.m7_plate": [preload("res://assets/audio/sfx/cooking/cozy-cafe-sfx/plate-place.wav"), -14, 75, false],
	"cooking.qte_perfect": [preload("res://assets/audio/sfx/ui/kenney_interface-sounds/tick_002.ogg"), -14, 75, false],
	"cooking.qte_good": [preload("res://assets/audio/sfx/ui/kenney_interface-sounds/tick_001.ogg"), -14, 75, false],
	"cooking.qte_miss": [preload("res://assets/audio/sfx/ui/kenney_interface-sounds/error_006.ogg"), -14, 75, false],
	"dialogue.advance": [preload("res://assets/audio/sfx/ui/kenney_interface-sounds/tick_001.ogg"), -22, 75, true],
	"emotion.angry": [preload("res://assets/audio/sfx/combat/kenney_impact-sounds/impactPunch_medium_000.ogg"), -20, 900, true],
	"emotion.happy": [preload("res://assets/audio/sfx/ui/kenney_interface-sounds/confirmation_001.ogg"), -20, 900, true],
	"emotion.proud": [preload("res://assets/audio/sfx/emotions/kenney_interface-sounds/pluck_001.ogg"), -20, 900, true],
	"emotion.puzzled": [preload("res://assets/audio/sfx/emotions/kenney_interface-sounds/question_001.ogg"), -20, 900, true],
	"emotion.troubled": [preload("res://assets/audio/sfx/emotions/kenney_interface-sounds/scratch_001.ogg"), -20, 900, true],
	"world.step0": [preload("res://assets/audio/sfx/world/kenney_rpg-audio/footstep00.ogg"), -25, 90, false],
	"world.step1": [preload("res://assets/audio/sfx/world/kenney_rpg-audio/footstep01.ogg"), -25, 90, false],
	"world.step2": [preload("res://assets/audio/sfx/world/kenney_rpg-audio/footstep02.ogg"), -25, 90, false],
}
const VOICES_PER_KIND: int = 6
var world_paused: bool = false
var _ui: Array[AudioStreamPlayer] = []
var _world: Array[AudioStreamPlayer] = []
var _last: Dictionary = {}
var _ui_cursor: int = 0
var _world_cursor: int = 0

func _ready() -> void:
	name = "SoundEffects"
	process_mode = Node.PROCESS_MODE_ALWAYS
	for kind: int in 2:
		for i: int in VOICES_PER_KIND:
			var player := AudioStreamPlayer.new()
			player.process_mode = Node.PROCESS_MODE_ALWAYS if kind == 0 else Node.PROCESS_MODE_PAUSABLE
			add_child(player)
			if kind == 0: _ui.append(player)
			else: _world.append(player)

static func owner_of(source: Node) -> TDSoundEffects:
	var current: Node = source
	while is_instance_valid(current):
		var candidate := current.get_node_or_null("SoundEffects") as TDSoundEffects
		if candidate != null: return candidate
		current = current.get_parent()
	return null

static func request(source: Node, event_id: String) -> bool:
	var owner := owner_of(source)
	return owner.play_event(event_id) if owner != null else false

static func stream_for(event_id: String) -> AudioStream:
	return EVENTS[event_id][0] as AudioStream if EVENTS.has(event_id) else null

func play_event(event_id: String) -> bool:
	if not is_inside_tree() or not EVENTS.has(event_id): return false
	var data: Array = EVENTS[event_id]
	var is_ui: bool = data[3]
	if not is_ui and (world_paused or get_tree().paused): return false
	var now := Time.get_ticks_msec()
	if now - int(_last.get(event_id, -100000)) < int(data[2]): return false
	var voices: Array[AudioStreamPlayer] = _ui if is_ui else _world
	if voices.is_empty(): return false
	var cursor: int = _ui_cursor if is_ui else _world_cursor
	var voice: AudioStreamPlayer = voices[cursor % voices.size()]
	if is_ui: _ui_cursor += 1
	else: _world_cursor += 1
	_last[event_id] = now
	voice.stop()
	voice.stream = data[0]
	voice.volume_db = float(data[1])
	voice.stream_paused = false
	voice.play()
	played.emit(event_id, voice.stream.resource_path)
	return true

func set_world_paused(value: bool) -> void:
	world_paused = value
	for voice: AudioStreamPlayer in _world: voice.stream_paused = value

func stop_all() -> void:
	for voice: AudioStreamPlayer in _ui + _world:
		voice.stop()
		voice.stream = null
	_last.clear()

func _exit_tree() -> void:
	stop_all()
