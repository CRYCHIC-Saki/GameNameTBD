extends VNEngineCommand
## A single blocking hand-off. No timer or game state is owned by this command.
var host: WeakRef
var kind: String

func _init(owner_node: Node, command_kind: String) -> void:
	host = weakref(owner_node)
	kind = command_kind

func command_name() -> String:
	return kind

func is_blocking() -> bool:
	return true

func apply(args: String, ctx: VNEngineCommandContext) -> void:
	var owner_node: Node = host.get_ref()
	if owner_node != null: owner_node.begin_block(kind, args, ctx)
