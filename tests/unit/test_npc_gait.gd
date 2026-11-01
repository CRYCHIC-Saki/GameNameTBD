extends GutTest

func test_distance_cycle_pause_stop_teleport_and_instance_isolation() -> void:
	var a:=TDNpcGait.new();var b:=TDNpcGait.new()
	a.reset(Vector2.ZERO);b.reset(Vector2.ZERO)
	var seen: Dictionary={}
	for x: int in range(1,114): a.sample(Vector2(x,0));seen[a.frame]=true
	assert_eq(seen.size(),4);assert_eq(a.facing,Vector2i.RIGHT);assert_eq(b.frame,-1)
	var held: int=a.frame;a.sample(Vector2(114,0),true);assert_eq(a.frame,held)
	a.sample(Vector2(114,0));assert_eq(a.frame,-1,"Waiting cannot march in place")
	a.sample(Vector2(2000,2000));assert_eq(a.frame,-1,"Scene relocation is not a stride")
	a.sample(Vector2(2000,1990));assert_eq(a.facing,Vector2i.UP);assert_gte(a.frame,0)
	a.sample(Vector2(2000,1980),false,true);assert_eq(a.frame,-1,"Sitting overrides displacement")

func test_named_actors_keep_original_idle_and_have_distinct_opposite_strides() -> void:
	for who: String in ["aling","chen"]:
		for face: Vector2i in [Vector2i.DOWN,Vector2i.UP,Vector2i.LEFT,Vector2i.RIGHT]:
			var idle:=TDStoryArt.sprite(who,face)
			assert_same(TDStoryArt.sprite(who,face,1),idle);assert_same(TDStoryArt.sprite(who,face,3),idle)
			var a:=TDStoryArt.sprite(who,face,0);var b:=TDStoryArt.sprite(who,face,2)
			assert_ne(a.get_image().get_data(),b.get_image().get_data())
			assert_gt(a.get_height(),300);assert_lte(a.get_height(),512)
			assert_lt(a.get_width(),384);assert_same(TDStoryArt.sprite(who,face,0),a)
