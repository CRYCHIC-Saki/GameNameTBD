class_name TDKitchenPlayer
extends CharacterBody2D

## Feet remain the collision origin. Visual frames never move the physics body.
const WALK_SPEED: float = 230.0
var controls_enabled: bool = true
var body_lift: float = 47.0
var confine_to: Callable = Callable()
var facing := Vector2i.DOWN
var motion_transform := Transform2D.IDENTITY
var input_transform := Transform2D.IDENTITY
var walk_speed: float=WALK_SPEED
@export_range(1.0, 3.0, 0.05) var sprint_multiplier: float = 1.6
var directional_art: bool=true
@export var sprite_height: float = 70.0
var walk_cycle_distance: float = 140.0
var vertical_stride_multiplier: float = 1.0
var _walk_time: float = 0.0
var _walk_phase: float = 0.0
var walk_frame: int = -1
var _sprite: Sprite2D
var _sprite_scale: Vector2

func _ready() -> void:
	_sprite = $Sprite2D as Sprite2D
	if directional_art:
		body_lift=sprite_height*.5
		_apply_directional_pose()
	_sprite_scale = _sprite.scale
	texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR

func face(direction: Vector2) -> void:
	if direction.is_zero_approx(): return
	facing=Vector2i(int(signf(direction.x)),0) if absf(direction.x)>absf(direction.y) else Vector2i(0,int(signf(direction.y)))
	if directional_art and is_instance_valid(_sprite):
		_apply_directional_pose()

func animation_texture() -> Texture2D:
	return TDChefArt.texture(facing, walk_frame)

func _apply_directional_pose() -> void:
	_sprite.texture = animation_texture()
	_sprite.centered = true
	_sprite.flip_h = false
	_sprite.rotation = 0.0
	_sprite.scale = Vector2.ONE * sprite_height / _sprite.texture.get_height()
	_sprite.position = Vector2(0.0, -sprite_height * 0.5)

func faces_target(target: Vector2) -> bool:
	var offset:=motion_transform.basis_xform_inv(target-position)
	return offset.length()<1.0 or offset.normalized().dot(Vector2(facing))>=0.6

func set_controls_enabled(enabled: bool) -> void:
	controls_enabled = enabled
	if not enabled:
		velocity = Vector2.ZERO
		_reset_pose()

func screen_input(direction: Vector2) -> Vector2:
	# Input axes and physics projection are separate. Normalize the projected
	# heading so diagonals retain the same visible speed and analogue strength.
	return input_transform.basis_xform(direction).normalized() * direction.length()

func _physics_process(delta: float) -> void:
	var before_motion := position
	var direction := Vector2.ZERO
	if controls_enabled:
		direction = Input.get_vector("world_left", "world_right", "world_up", "world_down")
	direction = screen_input(direction)
	face(direction)
	var speed := walk_speed * (sprint_multiplier if controls_enabled and Input.is_action_pressed("world_sprint") else 1.0)
	var motion := motion_transform.basis_xform(direction * speed)
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
		if motion_transform == Transform2D.IDENTITY:
			move_and_slide()
		else:
			_move_projected(motion * delta)
			velocity = (position - before_motion) / delta if delta > 0.0 else Vector2.ZERO
	# Convert actual travel back to screen space (the restaurant uses inverse projection).
	# Input or requested velocity alone would keep walking into a solid wall forever.
	# The isometric inverse projection is not orthonormal. basis_xform_inv
	# transposes it and would count horizontal pixels twice and vertical pixels
	# eight times. Use the actual affine inverse when measuring animation travel.
	var screen_travel := motion_transform.affine_inverse().basis_xform(position - before_motion)
	if directional_art:
		if controls_enabled and screen_travel.length_squared() > 0.0001:
			var stride_scale := vertical_stride_multiplier if facing.y != 0 else 1.0
			var cycle_length := maxf(walk_cycle_distance * stride_scale, 1.0)
			# Art size is independent of stride. Normalized phase also avoids a
			# pose jump when turning between directions with different strides.
			_walk_phase = fposmod(_walk_phase + screen_travel.length() / cycle_length, 1.0)
			walk_frame = mini(int(_walk_phase * 4.0), 3)
			_apply_directional_pose()
		else:
			_reset_pose()
	elif velocity.length_squared() > 1.0:
		_walk_time += delta
		var step := sin(_walk_time * 14.0)
		_sprite.position.y = -body_lift - absf(step) * 3.0
		_sprite.rotation = step * 0.035
		_sprite.scale = _sprite_scale * Vector2(1.0 + absf(step) * 0.02, 1.0 - absf(step) * 0.02)
		if not directional_art and absf(direction.x) > 0.1:
			_sprite.flip_h = direction.x < 0.0
	else:
		_reset_pose()

func _move_projected(motion: Vector2) -> void:
	# FLOATING move_and_slide preserves WORLD speed after a hit. An isometric
	# projection has unequal axes, so that can accelerate the visible character.
	# Sweep with real collisions; project the remainder onto the visible wall
	# tangent and keep the total screen travel within this tick's input budget.
	var to_screen := motion_transform.affine_inverse()
	var remaining := motion
	var budget := to_screen.basis_xform(motion).length()
	for iteration: int in max_slides:
		if remaining.length_squared() < 0.000001 or budget <= 0.000001: break
		remaining = motion_transform.basis_xform(to_screen.basis_xform(remaining).limit_length(budget))
		var before := position
		var collision := move_and_collide(remaining, false, safe_margin)
		budget = maxf(0.0, budget - to_screen.basis_xform(position - before).length())
		if collision == null: break
		var normal := collision.get_normal()
		var tangent := to_screen.basis_xform(normal.orthogonal()).normalized()
		var rest := to_screen.basis_xform(collision.get_remainder())
		remaining = motion_transform.basis_xform(tangent * rest.dot(tangent))
		# The screen tangent is not perpendicular to the wall in grid space.
		# Leaving that component in makes the next step re-enter the wall and shake at the door.
		var into := remaining.dot(normal)
		if into < 0.0:
			remaining -= normal * into

func _reset_pose() -> void:
	_walk_time = 0.0
	_walk_phase = 0.0
	walk_frame = -1
	if is_instance_valid(_sprite):
		if directional_art:
			_apply_directional_pose()
			return
		_sprite.position.y = -body_lift
		_sprite.rotation = 0.0
		_sprite.scale = _sprite_scale
