class_name TDPlayerPreferences
extends RefCounted
var values: Dictionary={"schema_version":1,"volume":0.75,"fullscreen":false}
var store: TDResearchStore

func _init(path: String) -> void:
	store=TDResearchStore.new(path,validate)
	var result:=store.load_game()
	if result.ok: values=result.data.duplicate(true)

func validate(raw: Variant) -> TDOutcome:
	if not raw is Dictionary or raw.get("schema_version")!=1: return TDOutcome.new(false,"UNSUPPORTED_VERSION")
	if not raw.get("fullscreen") is bool or not (raw.get("volume") is float or raw.get("volume") is int) or not is_finite(float(raw.volume)) or raw.volume<0 or raw.volume>1: return TDOutcome.new(false,"INVALID_SETTINGS")
	return TDOutcome.new(true,"VALID")

func apply() -> void:
	AudioServer.set_bus_volume_db(0,linear_to_db(maxf(.0001,float(values.volume))))
	AudioServer.set_bus_mute(0,float(values.volume)<=0)
	if DisplayServer.get_name()!="headless": DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if values.fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)

func change(volume: float, fullscreen: bool) -> TDOutcome:
	var next:Dictionary={"schema_version":1,"volume":volume,"fullscreen":fullscreen}
	var checked:=validate(next)
	if not checked.ok: return checked
	if DirAccess.make_dir_recursive_absolute(store.path.get_base_dir())!=OK: return TDOutcome.new(false,"DIRECTORY_FAILED")
	var result:=store.save_game(next)
	if result.ok: values=next;apply()
	return result
