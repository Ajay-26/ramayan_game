class_name CameraRig
extends Node3D
## Player-controlled third-person camera (God of War 2018 style).
##   - Mouse / right stick orbits the camera around Rama.
##   - While Rama aims (hold right click / LT) it slides in over his right
##     shoulder and narrows the view for precise bow shots.
##   - Walls and trees between Rama and the camera pull it in.

@export var target_path: NodePath
## Height of the orbit point above Rama's feet.
@export var pivot_height := 1.6
@export var distance := 4.6
@export var fov := 62.0
@export var default_pitch_degrees := -14.0
@export var min_pitch_degrees := -60.0
@export var max_pitch_degrees := 35.0
@export var mouse_sensitivity := 0.0025
@export var stick_sensitivity := 2.8
@export_group("Aiming")
## Over-the-shoulder offset while aiming: right, up (from pivot), back.
@export var aim_offset := Vector3(0.7, 0.05, 1.9)
@export var aim_fov := 48.0
@export_group("Shake")
@export var max_shake_offset := 0.25
@export var max_shake_roll := 0.03

var yaw := 0.0
var pitch := 0.0
var _target: Node3D
var _pivot := Vector3.ZERO
var _aim_blend := 0.0
var _distance_scale := 1.0
var _distance_scale_target := 1.0
var _fov_extra := 0.0
var _arm := 1.0
var _arm_target := 1.0
var _noise := FastNoiseLite.new()
var _noise_time := 0.0

@onready var camera: Camera3D = $Camera3D


func _ready() -> void:
	# The rig moves every rendered frame itself, so it must not be physics-interpolated.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_to_group("camera_rig")
	_target = get_node_or_null(target_path) as Node3D
	camera.current = true
	camera.fov = fov
	snap()


## Put the camera straight behind Rama (after a teleport / respawn).
func snap() -> void:
	if _target == null:
		return
	var facing: Variant = _target.get("facing")
	if facing is Vector3:
		yaw = atan2(-facing.x, -facing.z)
	pitch = deg_to_rad(default_pitch_degrees)
	_pivot = _target.global_position + Vector3.UP * pivot_height
	_apply(0.0)


## Turn the camera to look at a world point (used by tests and cutscene beats).
func look_toward(point: Vector3) -> void:
	var from := _pivot if _pivot != Vector3.ZERO else global_position
	var dir := (point - from).normalized()
	yaw = atan2(-dir.x, -dir.z)
	pitch = clampf(asin(dir.y), deg_to_rad(min_pitch_degrees), deg_to_rad(max_pitch_degrees))


## Pull the camera further out (e.g. the boss arena). 1.0 = normal.
func set_framing(distance_scale: float, extra_fov: float = 0.0) -> void:
	_distance_scale_target = distance_scale
	_fov_extra = extra_fov


## Flat forward direction the camera is looking (for camera-relative movement).
func forward_flat() -> Vector3:
	return Vector3.FORWARD.rotated(Vector3.UP, yaw)


## World point under the crosshair (screen center), up to `max_distance`.
func crosshair_point(max_distance: float, exclude: Array[RID]) -> Vector3:
	var center := get_viewport().get_visible_rect().size * 0.5
	var origin := camera.project_ray_origin(center)
	var dir := camera.project_ray_normal(center)
	var params := PhysicsRayQueryParameters3D.create(origin, origin + dir * max_distance,
		Combat.LAYER_WORLD | Combat.LAYER_ENEMY, exclude)
	var hit := get_world_3d().direct_space_state.intersect_ray(params)
	return hit["position"] if not hit.is_empty() else origin + dir * max_distance


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sens := mouse_sensitivity * lerpf(1.0, 0.6, _aim_blend)
		yaw -= event.relative.x * sens
		pitch = clampf(pitch - event.relative.y * sens, deg_to_rad(min_pitch_degrees), deg_to_rad(max_pitch_degrees))


func _process(delta: float) -> void:
	if _target == null:
		return
	var stick := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if stick != Vector2.ZERO:
		yaw -= stick.x * stick_sensitivity * delta
		pitch = clampf(pitch - stick.y * stick_sensitivity * 0.7 * delta, deg_to_rad(min_pitch_degrees), deg_to_rad(max_pitch_degrees))
	var aiming: bool = _target.get("is_aiming") == true
	_aim_blend = move_toward(_aim_blend, 1.0 if aiming else 0.0, delta * 6.0)
	_distance_scale = lerpf(_distance_scale, _distance_scale_target, 1.0 - exp(-2.0 * delta))
	_apply(delta)
	_apply_shake(delta)


func _physics_process(_delta: float) -> void:
	if _target == null:
		return
	var pivot := _target.global_position + Vector3.UP * pivot_height
	var desired := pivot + _offset()
	var params := PhysicsRayQueryParameters3D.create(pivot, desired, Combat.LAYER_WORLD)
	var hit := get_world_3d().direct_space_state.intersect_ray(params)
	if hit.is_empty():
		_arm_target = 1.0
	else:
		var full := pivot.distance_to(desired)
		_arm_target = clampf((pivot.distance_to(hit["position"]) - 0.3) / maxf(full, 0.01), 0.1, 1.0)


func _offset() -> Vector3:
	var basis := Basis.from_euler(Vector3(pitch, yaw, 0.0))
	var orbit := basis * Vector3(0.0, 0.0, distance * _distance_scale)
	var shoulder := basis * Vector3(aim_offset.x, 0.0, aim_offset.z) + Vector3.UP * aim_offset.y
	return orbit.lerp(shoulder, _aim_blend)


func _apply(delta: float) -> void:
	var target_pivot := _target.get_global_transform_interpolated().origin + Vector3.UP * pivot_height
	_pivot = target_pivot if delta == 0.0 else _pivot.lerp(target_pivot, 1.0 - exp(-16.0 * delta))
	# Pull in fast when something blocks the view, ease back out slowly.
	_arm = _arm_target if delta == 0.0 else move_toward(_arm, _arm_target, delta * (8.0 if _arm_target < _arm else 2.0))
	global_position = _pivot + _offset() * _arm
	camera.global_basis = Basis.from_euler(Vector3(pitch, yaw, 0.0))
	camera.fov = lerpf(fov + _fov_extra, aim_fov, _aim_blend)


## Screen shake from FX.trauma. Uses real time, so it keeps shaking during hit-stop.
func _apply_shake(delta: float) -> void:
	_noise_time += delta / maxf(Engine.time_scale, 0.001)
	var strength := FX.trauma * FX.trauma
	camera.h_offset = _noise.get_noise_2d(_noise_time * 60.0, 0.0) * max_shake_offset * strength
	camera.v_offset = _noise.get_noise_2d(0.0, _noise_time * 60.0) * max_shake_offset * strength
	camera.rotate_object_local(Vector3.BACK, _noise.get_noise_2d(_noise_time * 60.0, 100.0) * max_shake_roll * strength)
