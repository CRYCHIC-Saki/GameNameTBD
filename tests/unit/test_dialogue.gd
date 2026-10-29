extends GutTest

func test_click_reveals_then_a_choice_blocks_skip_until_answered() -> void:
	var talk := _sample()
	talk.begin()
	assert_eq(talk.visible_text(), "")
	talk.tick(TDDialogue.TYPE_SEC)
	assert_eq(talk.visible_text(), "一")
	talk.click()
	assert_eq(talk.visible_text(), "一二三")
	talk.click()
	assert_true(talk.choices_open)
	talk.click()
	talk.skip()
	assert_true(talk.choices_open)
	assert_false(talk.pick("missing"))
	assert_true(talk.pick("ask"))
	assert_false(talk.choices_open)
	assert_eq(talk.picks, ["ask"])
	assert_eq(talk.visible_text(), "")
	talk.click()
	assert_eq(talk.full_text(), "林夏：想吃热菜。")
	talk.skip()
	assert_true(talk.finished)

func test_holding_the_pointer_fast_forwards_and_stops_on_a_choice() -> void:
	var talk := _sample()
	talk.begin()
	talk.pointer_down()
	talk.hold(TDDialogue.HOLD_ARM, true)
	assert_true(talk.choices_open)
	assert_false(talk.finished)
	talk.release()
	assert_true(talk.choices_open)
	talk.force_close()
	assert_true(talk.finished)

func test_caller_and_guest_replies_do_not_change_their_state() -> void:
	var caller := TDTownCaller.new()
	caller.boot(Vector2i(0, 0), Vector2i(2, 0))
	var talk := caller.conversation()
	talk.begin()
	talk.skip()
	assert_true(talk.choices_open)
	assert_eq(talk.options().size(), 2)
	assert_true(talk.pick("stroll"))
	assert_eq(caller.phase, "wander")
	assert_false(caller.ate)
	var guest := TDGuestVisit.conversation("林夏", "番茄炒蛋", "wait_serve", "linxia")
	guest.begin()
	guest.skip()
	assert_eq(String((guest.options()[0] as Dictionary).id), "soon")
	assert_true(guest.pick("hurry"))
	assert_true(guest.full_text().contains("不另算"))

func test_the_box_dims_the_room_and_mouse_choices_close_it() -> void:
	var layer := CanvasLayer.new()
	add_child_autofree(layer)
	var view := TDDialogueView.new()
	layer.add_child(view)
	await get_tree().process_frame
	var endings: Array = []
	view.closed.connect(func(text: String, picks: Array) -> void: endings.append({"text": text, "picks": picks}))
	view.present(_sample())
	assert_gt(view.dim_alpha(), 0.5)
	assert_eq(view.get_node("Portrait").get("who"), "linxia")
	assert_eq((view.get_node("Box/Speaker") as Label).text, "林夏")
	_tap(view)
	assert_eq((view.get_node("Box/Body") as Label).text, "一二三")
	_tap(view)
	assert_true((view.get_node("Box/Skip") as Button).disabled)
	assert_eq(view.get_node("Box/Choices").get_child_count(), 2)
	(view.get_node("Box/Choices").get_child(0) as Button).pressed.emit()
	_tap(view)
	assert_eq(view.get_node("Box/Body").text, "林夏：想吃热菜。")
	view._on_skip()
	assert_false(view.visible)
	assert_eq(endings.size(), 1)
	assert_eq(endings[0].text, "林夏：想吃热菜。")
	assert_eq(endings[0].picks, ["ask"])

func _sample() -> TDDialogue:
	var talk := TDDialogue.new()
	talk.add_line("林夏", "linxia", "一二三")
	talk.add_choice([
		{"id": "ask", "label": "今天想吃点什么？", "text": "林夏：想吃热菜。", "speaker": "林夏", "portrait": "linxia"},
		{"id": "stroll", "label": "你先逛逛。", "text": "林夏：我再走走。", "speaker": "林夏", "portrait": "linxia"},
	])
	return talk

func _tap(view: TDDialogueView) -> void:
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	view._gui_input(down)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	view._gui_input(up)
