extends GutTest

func test_runtime_index_preserves_all_source_identities_without_flavor_conversion() -> void:
	var source: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://doc/source/ingredients.json"))
	var runtime: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(TDIngredientBook.SOURCE))
	assert_eq(runtime.schema_version,1.0)
	assert_eq(runtime.source_sha256,FileAccess.get_sha256("res://doc/source/ingredients.json"))
	assert_eq(runtime.categories.size(),source.categories.size())
	var count:int=0
	var book:=TDIngredientBook.new()
	assert_true(book.load_file().ok)
	for i:int in source.categories.size():
		var expected:Dictionary=source.categories[i]
		var actual:Dictionary=runtime.categories[i]
		assert_eq(actual.id,expected.id)
		assert_eq(actual.name,expected.name)
		assert_eq(actual.items.size(),expected.items.size())
		for j:int in expected.items.size():
			var item:Dictionary=expected.items[j]
			assert_eq(actual.items[j],{"id":item.id,"name":item.name,"sub":item.get("sub","")})
			assert_eq(book.get_item(item.id).name,item.name)
			count+=1
	assert_eq(book.items.size(),count)
	var isolated:=book.get_item("tomato");isolated.name="changed"
	assert_ne(book.get_item("tomato").name,"changed")
