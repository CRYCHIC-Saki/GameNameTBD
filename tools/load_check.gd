extends SceneTree

var checked: int = 0
var failures: int = 0

func _initialize() -> void:
	for directory: String in ["res://src", "res://dev"]:
		visit(directory)
	var catalog := TDCatalog.new()
	var outcome := catalog.load_file("res://content/dev_samples.json")
	if not outcome.ok:
		printerr(outcome.message)
		failures += 1
	var recipes := TDRecipeCatalog.new()
	var service:=TDServiceCatalog.new()
	var service_result:=service.load_file()
	if not service_result.ok:
		printerr(service_result.message); failures+=1
	var full := TDCookingCatalog.new()
	var full_result := full.load_file("res://content/cooking_system.json")
	if not full_result.ok:
		printerr(full_result.message)
		failures += 1
	var towns := TDTownCatalog.new()
	var town_result := towns.load_file()
	if not town_result.ok:
		printerr(town_result.message)
		failures += 1
	var restaurant_catalog := TDRestaurantCatalog.new()
	var restaurant_result := restaurant_catalog.load_file()
	if not restaurant_result.ok:
		printerr(restaurant_result.message)
		failures += 1
	var recipe_result := recipes.load_file("res://content/cooking_prototype.json")
	if not recipe_result.ok:
		printerr(recipe_result.message)
		failures += 1
	print("LOAD_CHECK resources=%d failures=%d" % [checked, failures])
	quit(1 if failures > 0 or checked == 0 else 0)

func visit(directory: String) -> void:
	for file: String in DirAccess.get_files_at(directory):
		if file.ends_with(".gd") or file.ends_with(".tscn"):
			var resource := load(directory.path_join(file))
			checked += 1
			if resource == null:
				failures += 1
			elif resource is PackedScene:
				var node: Node = resource.instantiate()
				if node == null:
					failures += 1
				else:
					node.free()
	for child: String in DirAccess.get_directories_at(directory):
		visit(directory.path_join(child))
