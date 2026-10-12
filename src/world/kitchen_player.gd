class_name TDKitchenPlayer
extends CharacterBody2D

## Feet are the movement/collision origin; the generated sprite rises above it.
const WALK_SPEED: float = 230.0
var controls_enabled: bool = true
var body_lift: float = 47.0
var confine_to: Callable = Callable()
var _walk_time: float = 0.0
var _sprite: Sprite2D
var _sprite_scale: Vector2

func _ready() -> void:
	_sprite = $Sprite2D as Sprite2D
	_sprite_scale = _sprite.scale

func set_controls_enabled(enabled: bool) -> void:
	controls_enabled = enabled
	if not enabled:
		velocity = Vector2.ZERO
		_reset_pose()

func _physics_process(delta: float) -> void:
	var direction := Vector2.ZERO
	if controls_enabled:
		direction = Input.get_vector("world_left", "world_right", "world_up", "world_down")
	var motion := direction * WALK_SPEED
	if confine_to.is_valid():
		var travel := motion * delta
		var proposed := position + travel
		if travel != Vector2.ZERO and not bool(confine_to.call(proposed)):
			var across := position + Vector2(travel.x, 0.0)
			var along := position + Vector2(0.0, travel.y)
			if travel.x != 0.0 and bool(confine_to.call(across)):
				proposed = across
				motion.y = 0.0
			elif travel.y != 0.0 and bool(confine_to.call(along)):
				proposed = along
				motion.x = 0.0
			else:
				proposed = position
				motion = Vector2.ZERO
		position = proposed
		velocity = motion
	else:
		velocity = motion
		move_and_slide()
	if velocity.length_squared() > 1.0:
		_walk_time += delta
		var step := sin(_walk_time * 14.0)
		_sprite.position.y = -body_lift - absf(step) * 3.0
		_sprite.rotation = step * 0.035
		_sprite.scale = _sprite_scale * Vector2(1.0 + absf(step) * 0.02, 1.0 - absf(step) * 0.02)
		if absf(direction.x) > 0.1:
			_sprite.flip_h = direction.x < 0.0
	else:
		_reset_pose()

func _reset_pose() -> void:
	_walk_time = 0.0
	if is_instance_valid(_sprite):
		_sprite.position.y = -body_lift
		_sprite.rotation = 0.0
		_sprite.scale = _sprite_scale
