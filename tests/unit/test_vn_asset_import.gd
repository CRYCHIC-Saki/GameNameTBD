extends GutTest
const Importer := preload("res://addons/td_vn_editor/asset_import.gd")
var importer: Importer
var source: String
var original_cast: PackedByteArray
var original_preset: PackedByteArray

func before_each() -> void:
	importer = Importer.new()
	importer.root = "res://.godot/td_vn_editor/import_tests/"+str(Time.get_ticks_usec())+"/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(importer.path(Importer.CAST).get_base_dir()))
	DirAccess.copy_absolute(ProjectSettings.globalize_path("res://"+Importer.CAST),ProjectSettings.globalize_path(importer.path(Importer.CAST)))
	var config := "[preset.0]\nname=\"Windows Framework Demo\"\nexport_filter=\"resources\"\nexport_files=PackedStringArray(\"res://src/main.tscn\")\n\n[preset.0.options]\ncustom_key=\"preserved\"\n"
	_write(importer.path(Importer.PRESET),config.to_utf8_buffer())
	source = importer.path("来源 空格 测试.png")
	var image := Image.create(16,24,false,Image.FORMAT_RGBA8); image.fill(Color(.3,.7,.2,.5)); image.save_png(source)
	original_cast = FileAccess.get_file_as_bytes(importer.path(Importer.CAST))
	original_preset = FileAccess.get_file_as_bytes(importer.path(Importer.PRESET))

func _write(target: String, bytes: PackedByteArray) -> void:
	var file := FileAccess.open(target,FileAccess.WRITE); file.store_buffer(bytes); file.close()

func test_background_copies_original_and_registers_precise_export_paths() -> void:
	var hash := FileAccess.get_sha256(source)
	var plan: Dictionary = importer.prepare(source,"background","雨夜港口")
	assert_eq(plan.error,"")
	assert_false(FileAccess.file_exists(plan.reference),"preparation is not publication")
	var result: Dictionary = importer.commit(plan)
	assert_eq(result.error,"")
	assert_eq(FileAccess.get_sha256(result.image),hash)
	assert_eq(FileAccess.get_sha256(source),hash,"source read-only")
	assert_eq(Importer.resource_title(result.reference,""),"雨夜港口")
	var config := ConfigFile.new(); assert_eq(config.load(importer.path(Importer.PRESET)),OK)
	assert_true(result.reference in config.get_value("preset.0","export_files"))
	assert_true(result.image in config.get_value("preset.0","export_files"))
	assert_eq(config.get_value("preset.0.options","custom_key"),"preserved")
	assert_eq(FileAccess.get_file_as_bytes(importer.path(Importer.CAST)),original_cast)
	assert_ne(importer.prepare(source,"background","雨夜港口").error,"")

func test_new_character_and_added_expression_keep_existing_cast() -> void:
	var first: Dictionary = importer.commit(importer.prepare(source,"character","小李"))
	assert_eq(first.error,"")
	var cast: VNEngineCast = ResourceLoader.load(importer.path(Importer.CAST),"",ResourceLoader.CACHE_MODE_IGNORE)
	assert_eq(cast.characters.size(),(load("res://"+Importer.CAST) as VNEngineCast).characters.size()+1)
	assert_eq(cast.get_entry("aling").display_name,"阿铃")
	assert_eq(cast.get_entry(first.character).display_name,"小李")
	assert_eq(cast.get_entry(first.character).default_expression,"calm")
	assert_true(first.reference.ends_with("_base_base_calm_mid.tres"))
	var cast_after := FileAccess.get_file_as_bytes(importer.path(Importer.CAST))
	var expression: Dictionary = importer.commit(importer.prepare(source,"expression","惊讶",first.character))
	assert_eq(expression.error,"")
	assert_eq(Importer.resource_title(expression.reference,""),"惊讶")
	assert_eq(FileAccess.get_file_as_bytes(importer.path(Importer.CAST)),cast_after)
	assert_ne(importer.prepare(source,"character","小李").error,"")
	assert_ne(importer.prepare(source,"expression","惊讶",first.character).error,"")

func test_empty_name_missing_actor_invalid_type_and_broken_file_rejected() -> void:
	assert_ne(importer.prepare(source,"background","").error,"")
	assert_ne(importer.prepare(source,"expression","愤怒","missing").error,"")
	assert_ne(importer.prepare(source,"audio","音效").error,"")
	assert_ne(Importer.inspect_image(source+".exe").error,"")
	var broken := importer.path("broken.png"); _write(broken,"bad".to_utf8_buffer())
	assert_ne(Importer.inspect_image(broken).error,"")
	_write(broken,"This is not a PNG image even with enough bytes.".to_utf8_buffer())
	assert_ne(Importer.inspect_image(broken).error,"")
	assert_eq(FileAccess.get_file_as_bytes(importer.path(Importer.CAST)),original_cast)
	assert_eq(FileAccess.get_file_as_bytes(importer.path(Importer.PRESET)),original_preset)

func test_cancelled_prepare_does_not_create_asset_or_change_registrations() -> void:
	var plan: Dictionary = importer.prepare(source,"character","取消测试")
	assert_eq(plan.error,"")
	assert_false(FileAccess.file_exists(plan.image))
	assert_false(FileAccess.file_exists(plan.reference))
	assert_eq(FileAccess.get_file_as_bytes(importer.path(Importer.CAST)),original_cast)
	assert_eq(FileAccess.get_file_as_bytes(importer.path(Importer.PRESET)),original_preset)

func test_concurrent_export_edit_is_not_overwritten() -> void:
	var plan: Dictionary = importer.prepare(source,"character","并发测试")
	_write(importer.path(Importer.PRESET),original_preset+"\n; Other editor\n".to_utf8_buffer())
	var changed := FileAccess.get_file_as_bytes(importer.path(Importer.PRESET))
	assert_ne(importer.commit(plan).error,"")
	assert_eq(FileAccess.get_file_as_bytes(importer.path(Importer.PRESET)),changed)
	assert_false(FileAccess.file_exists(plan.image))
	assert_eq(FileAccess.get_file_as_bytes(importer.path(Importer.CAST)),original_cast)

func test_partial_write_failure_restores_cast_export_and_removes_new_images() -> void:
	for stop_at: int in [1,2,3,4]:
		var plan: Dictionary = importer.prepare(source,"character","失败恢复"+str(stop_at))
		importer.fail_after_writes = stop_at
		assert_ne(importer.commit(plan).error,"")
		assert_false(FileAccess.file_exists(plan.image))
		assert_false(FileAccess.file_exists(plan.reference))
		assert_eq(FileAccess.get_file_as_bytes(importer.path(Importer.CAST)),original_cast)
		assert_eq(FileAccess.get_file_as_bytes(importer.path(Importer.PRESET)),original_preset)

func test_duplicate_commit_cannot_overwrite_first_import() -> void:
	var plan: Dictionary = importer.prepare(source,"background","双击")
	assert_eq(importer.commit(plan).error,"")
	var hash := FileAccess.get_sha256(importer.path(Importer.PRESET))
	assert_ne(importer.commit(plan).error,"")
	assert_eq(FileAccess.get_sha256(importer.path(Importer.PRESET)),hash)

func test_jpg_and_webp_sources_preserve_bytes_and_dimensions() -> void:
	var image := Image.create(32,20,false,Image.FORMAT_RGB8); image.fill(Color.BISQUE)
	for extension: String in ["jpg","webp"]:
		var file := importer.path("image."+extension)
		if extension == "jpg": image.save_jpg(file)
		else: image.save_webp(file)
		var inspected := Importer.inspect_image(file)
		assert_eq(inspected.error,"")
		assert_eq(inspected.image.get_size(),Vector2i(32,20))
		var result: Dictionary = importer.commit(importer.prepare(file,"background",extension))
		assert_eq(result.error,"")
		assert_eq(FileAccess.get_sha256(result.image),FileAccess.get_sha256(file))
