extends Control
## F6 developer preview. No profile or gameplay save is loaded or created.
var view: TDDialogueView
var music: TDGameMusic

func _ready() -> void:
	view=TDDialogueView.new();add_child(view)
	music=TDGameMusic.new();add_child(music)
	var bar:=HBoxContainer.new();bar.position=Vector2(18,8);add_child(bar)
	for entry: Array in [["完整开篇","intro"],["A 到镇 14s","arrival"],["B 饥饿 6s","hungry"],["C 阿铃 10s","messenger"]]:
		var button:=Button.new();button.text=entry[0];button.focus_mode=Control.FOCUS_NONE
		button.pressed.connect(play.bind(entry[1]));bar.add_child(button)
	play("intro")

func play(id: String) -> void:
	var talk: TDDialogue
	if id=="intro": talk=TDOpeningScript.conversation("intro","？？？",80)
	else:
		talk=TDDialogue.new();talk.add_cg(id,"",TDArrivalCutscene.SPANS[id])
	view.present(talk)

func _process(_delta: float) -> void:
	if music!=null and view!=null: music.select_context("casual",view.presentation_paused)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and not event.is_echo(): view.toggle_presentation_pause();get_viewport().set_input_as_handled()
