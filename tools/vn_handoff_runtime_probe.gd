extends SceneTree
const Stage := preload("res://addons/td_vn_editor/preview_stage.gd")
const OUT := "res://artifacts/vn-handoff-20261116/editor/"
var checks:Array[Dictionary]=[]
func _initialize() -> void:run.call_deferred()
func expect(value:bool,label:String) -> void:
	checks.append({"pass":value,"name":label})
	if not value:printerr("HANDOFF_PLAY_FAIL "+label)
func run() -> void:
	root.size=Vector2i(1280,800)
	var fixture:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OUT+"fixture.json"))
	var stage:=Stage.new();root.add_child(stage);stage.draft_path=fixture.path;stage.start("？？？",true)
	await process_frame;await process_frame
	expect(stage.runner!=null,"real native runner")
	expect(stage.runner.current_text=="保存交接说明后仍能编辑这一页。","handoff not rendered as dialogue")
	expect(stage.runner.ctx.characters.active_sprites.has("hero"),"native actor displayed")
	expect(VNEngineMain.save_data().memory_only,"preview never opens player saves")
	stage.dialog._reveal_to_end();await create_timer(.5).timeout;RenderingServer.force_draw(true)
	expect(root.get_texture().get_image().save_png(OUT+"03-native-play.png")==OK,"native play screenshot")
	stage.reset();root.remove_child(stage);stage.queue_free();await process_frame;await process_frame
	expect(VNEngineMain.instance()==null,"preview releases singleton")
	var failures:=0
	for item:Dictionary in checks:
		if not item.pass:failures+=1
	var report:=FileAccess.open(OUT+"runtime-report.json",FileAccess.WRITE);report.store_string(JSON.stringify({"count":checks.size(),"failures":failures,"checks":checks},"\t"));report.close()
	print("VN_HANDOFF_PLAY checks=%d failures=%d"%[checks.size(),failures]);quit(1 if failures else 0)
