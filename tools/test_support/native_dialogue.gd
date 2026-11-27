extends RefCounted

static func completed_mainline(profile: TDGameProfile) -> void:
	profile.use_revised_mainline()
	var state := profile.story.revised
	for index: int in range(int(state.cursor),TDRevisedMainline.data().nodes.size()):
		var node: Dictionary = TDRevisedMainline.data().nodes[index]
		if node.kind=="dialogue":
			TDRevisedMainline.complete_dialogue(state,node.id,true)
		else:
			TDRevisedMainline.complete_action(state,node.id)

## Drive actual VN input. Never complete tasks by mutating TDDialogue.finished.
static func finish(view: TDDialogueView, tree: SceneTree) -> void:
	for _i: int in 120:
		if view.talk == null: return
		if not view._native:
			view.talk.skip(); view._emit_if_finished(); return
		if view.awaiting_name():
			view._hero_input.text = "测试厨神"; view._confirm_hero_name()
		elif view._vn_stage.runner != null:
			var runner := view._vn_stage.runner
			if not runner.current_choices.is_empty():
				runner.make_choice(runner.script_res.index_of(runner.current_choices[0].target))
			else:
				view._vn_stage.dialog._reveal_to_end()
				view._vn_stage.dialog._advance_dialog()
		await tree.process_frame; await tree.process_frame
