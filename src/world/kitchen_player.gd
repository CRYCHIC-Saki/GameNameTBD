class_name TDKitchenPlayer
extends CharacterBody2D

## Feet are the movement/collision origin; the generated sprite rises above it.
const WALK_SPEED: float = 230.0
var controls_enabled: bool = true
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
	velocity = direction * WALK_SPEED
	move_and_slide()
	if velocity.length_squared() > 1.0:
		_walk_time += delta
		var step := sin(_walk_time * 14.0)
		_sprite.position.y = -47.0 - absf(step) * 3.0
		_sprite.rotation = step * 0.035
		_sprite.scale = _sprite_scale * Vector2(1.0 + absf(step) * 0.02, 1.0 - absf(step) * 0.02)
		if absf(direction.x) > 0.1:
			_sprite.flip_h = direction.x < 0.0
	else:
		_reset_pose()

func _reset_pose() -> void:
	_walk_time = 0.0
	if is_instance_valid(_sprite):
		_sprite.position.y = -47.0
		_sprite.rotation = 0.0
		_sprite.scale = _sprite_scale
