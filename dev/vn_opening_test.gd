extends Control
## Isolated visual preview, without Profile, world rewards or disk writes.
var view: TDDialogueView

func _ready() -> void:
	view=TDDialogueView.new();add_child(view)
	view.closed.connect(func(_text:String,_picks:Array)->void:
		var button:=Button.new();button.text="重新预览港口开篇";button.position=Vector2(520,360)
		button.pressed.connect(func()->void:button.queue_free();play());add_child(button))
	play()

func play() -> void:
	var talk:=TDOpeningScript.conversation("intro","？？？",80)
	talk.context.request_name=true
	view.present(talk)
