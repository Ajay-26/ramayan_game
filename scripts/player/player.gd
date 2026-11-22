class_name Player
extends CharacterBody3D
## Rama (greybox).
##   Movement: camera-relative run, jump, dodge roll (i-frames), sneak (toggle).
##   Blades:   4-hit light chain, 2-hit heavy chain, soft lock-on, takedowns
##             on unaware enemies from behind.
##   Bow:      tap to shoot, hold to charge a piercing shot. Locks onto the best
##             target in front; Tab / right stick switches. Arrows through
##             torch flames catch fire.
##   Chakra:   thrown at the target, cuts along its path, returns to his hand.
##   Astra:    meter fills from dealing damage; when full, a divine blast.
##
## Attacks have a STARTUP phase (wind-up + lunge, the hit lands at its end) and a
## RECOVERY phase. Pressing attack during an attack buffers the next one.

signal health_changed(current: float, maximum: float)
signal died
signal astra_ready
signal chakra_unlocked

enum State { MOVE, ATTACK, DODGE, HURT, DEAD, TAKEDOWN, ASTRA }
enum Phase { STARTUP, RECOVERY }

## Every melee move. Light = fists, heavy = the sword (drawn just for the swing).
##   L, L, L  -> jab, cross, uppercut
##   L, H     -> jab, rising sword slash
##   L, L, H  -> jab, cross, overhead sword slam (hits all around)
##   H        -> a slow, heavy sword swing
const ATTACKS := {
	"jab": {"damage": 9.0, "startup": 0.1, "recovery": 0.3, "lunge": 3.0, "reach": 1.0, "radius": 1.0, "knockback": 2.5, "hitstop": 0.05, "shake": 0.1, "kind": "light", "anim": "Stab1", "anim_time": 0.6, "sword": false},
	"cross": {"damage": 10.0, "startup": 0.12, "recovery": 0.32, "lunge": 3.5, "reach": 1.0, "radius": 1.05, "knockback": 3.0, "hitstop": 0.06, "shake": 0.12, "kind": "light", "anim": "ShieldBash", "anim_time": 0.6, "sword": false},
	"uppercut": {"damage": 17.0, "startup": 0.18, "recovery": 0.5, "lunge": 4.0, "reach": 1.0, "radius": 1.3, "knockback": 9.0, "hitstop": 0.1, "shake": 0.3, "kind": "heavy", "anim": "SlashUppercut", "anim_time": 0.85, "sword": false},
	"heavy": {"damage": 34.0, "startup": 0.5, "recovery": 0.6, "lunge": 2.5, "reach": 1.5, "radius": 1.6, "knockback": 9.0, "hitstop": 0.12, "shake": 0.4, "kind": "heavy", "anim": "Heavy1", "anim_time": 1.35, "sword": true},
	"rising": {"damage": 28.0, "startup": 0.3, "recovery": 0.5, "lunge": 4.0, "reach": 1.4, "radius": 1.5, "knockback": 10.0, "hitstop": 0.11, "shake": 0.35, "kind": "heavy", "anim": "Slash1", "anim_time": 0.9, "sword": true},
	"slam": {"damage": 42.0, "startup": 0.42, "recovery": 0.7, "lunge": 2.0, "reach": 0.8, "radius": 2.6, "knockback": 12.0, "hitstop": 0.14, "shake": 0.55, "kind": "slam", "anim": "HeavyJumpAttack", "anim_time": 1.15, "sword": true, "shockwave": true},
}
const LIGHT_STRING := ["jab", "cross", "uppercut"]
## Heavy attack used after 0, 1 or 2 light hits.
const HEAVY_AFTER := ["heavy", "rising", "slam"]

@export var max_health := 100.0
@export var move_speed := 6.5
@export var sneak_speed := 2.8
@export var acceleration := 40.0
@export var jump_velocity := 7.5
@export var gravity := 22.0
@export var turn_speed := 18.0
@export_group("Dodge")
@export var dodge_speed := 14.0
@export var dodge_time := 0.38
@export var dodge_iframes := 0.3
@export_group("Melee")
## How long a button press is remembered while busy (seconds).
@export var input_buffer_time := 0.3
## Fraction of recovery that must play before the next attack can start.
@export var chain_point := 0.35
## Max distance to auto-aim melee attacks at an enemy.
@export var melee_target_range := 5.0
@export_group("Bow")
@export var arrow_scene: PackedScene
@export var lock_range := 30.0
@export var charge_time := 0.6
## Walking speed while aiming (stops completely while drawing).
@export var aim_move_speed := 2.4
## How close to the crosshair (fraction of screen height) aim assist reaches.
@export var aim_assist_screen := 0.07
@export var bow_cooldown := 0.3
@export_group("Chakra")
@export var chakra_scene: PackedScene
## Short reach: further than a sword swing, far shorter than an arrow.
@export var chakra_range := 7.0
@export_group("Astra")
@export var astra_max := 100.0
@export var astra_radius := 9.0
@export var astra_damage := 80.0

var health: float
var state := State.MOVE
## Direction Rama is facing, flat on the ground.
var facing := Vector3.FORWARD
var is_sneaking := false
## Holding aim (right click / LT): over-the-shoulder camera, left click fires.
var is_aiming := false
var has_chakra := false
var chakra_ready := true
var astra := 0.0
## What the bow and chakra will aim at (shown by the HUD reticle).
var current_target: Node3D
## An unaware enemy Rama can take down right now (HUD shows a prompt).
var takedown_candidate: Enemy
## 0..1 while drawing the bow, -1 when not drawing.
var bow_charge := -1.0

var _state_time := 0.0
var _phase := Phase.STARTUP
## Name of the melee move in progress ("" when not attacking).
var current_attack := ""
## Light hits landed so far in the current string (0-3).
var _light_count := 0
var _attack: Dictionary = {}
var _buffered := ""
var _buffer_left := 0.0
var _invuln_left := 0.0
var _dodge_dir := Vector3.FORWARD
var _lunge_target: Node3D
var _pose_tween: Tween
var _bow_cooldown_left := 0.0
var _target_refresh_left := 0.0
var _takedown_victim: Enemy
var _takedown_struck := false
var _astra_fired := false

@onready var visual: Node3D = $Visual
@onready var body_pivot: Node3D = $Visual/Body
@onready var blade_r: Node3D = $Visual/Body/BladePivotR
@onready var blade_l: Node3D = $Visual/Body/BladePivotL
@onready var bow_mesh: Node3D = $Visual/Body/Bow
## Animated body (optional: without it Rama falls back to the greybox shapes).
@onready var model: CharacterModel = get_node_or_null("Visual/Model")

## Where weapons sit on the mannequin's bones (taken from Cat's template rig).
const HAND_R := "Transform3D(-4.37114e-08, 1, -4.37114e-08, 0, -4.37114e-08, -1, -1, -4.37114e-08, 1.91069e-15, 0, 0.085, 0.025)"
const HAND_L := "Transform3D(-4.37114e-08, -1, 0, 1, -4.37114e-08, 0, 0, 0, 1, 0, 0.095, 0.02)"
const BACK := "Transform3D(0.0014642, 0.00341032, -0.999993, -0.0666676, -0.997769, -0.00350057, -0.997774, 0.0666723, -0.00123349, -0.120301, 0.214743, -0.165111)"

## While > 0, an action animation is playing and locomotion won't override it.
var _anim_lock := 0.0
var _hand_sword: Node3D
var _hip_sword: Node3D
var _snap_to_ground := false

var _rest_r := Vector3(deg_to_rad(-70), deg_to_rad(-15), 0)
var _rest_l := Vector3(deg_to_rad(-70), deg_to_rad(15), 0)
var _bow_back_pos := Vector3(0, 0.35, 0.3)
var _bow_back_rot := Vector3(0, 0, deg_to_rad(22))
var _bow_aim_pos := Vector3(-0.25, 0.4, -0.5)
var _bow_aim_rot := Vector3(0, 0, deg_to_rad(-8))


func _ready() -> void:
	add_to_group("player")
	health = max_health
	has_chakra = Game.has_chakra
	blade_r.rotation = _rest_r
	blade_l.rotation = _rest_l
	if model:
		_setup_model()
	health_changed.emit(health, max_health)


## Moves the blades, bow and crown onto the animated body's bones.
func _setup_model() -> void:
	# Blade meshes point along -Z; the hand pivots expect the weapon along +Y.
	var blade_fix := Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3.ZERO)
	var hand_r: Transform3D = str_to_var(HAND_R)
	var hand_l: Transform3D = str_to_var(HAND_L)
	var grip := Transform3D(Basis(), Vector3(0, 0, -0.42))
	_hand_sword = blade_r.get_node("Blade") as Node3D
	_hip_sword = blade_l.get_node("Blade") as Node3D
	model.attach(_hand_sword, "RightHand", hand_r * blade_fix * grip)
	# Sheathed at the left hip, pointing down and back.
	model.attach(_hip_sword, "Hips", Transform3D(Basis.from_euler(Vector3(deg_to_rad(115), 0, deg_to_rad(-12))), Vector3(0.2, 0.0, 0.05)))
	for sword in [_hand_sword, _hip_sword]:
		_add_sword_hilt(sword)
	_set_sword_drawn(false)
	(bow_mesh as MeshInstance3D).mesh = _build_bow_mesh()
	model.attach(bow_mesh, "UpperChest", str_to_var(BACK))
	model.attach($Visual/Body/Crown, "Head", Transform3D(Basis(), Vector3(0, 0.2, 0.0)))
	model.attach($Visual/Body/Dhoti, "Hips", Transform3D(Basis(), Vector3(0, -0.2, 0.0)))
	# Royal ornaments: gold necklace and a deep red sash (angavastram) across the chest.
	var gold := StandardMaterial3D.new()
	gold.albedo_color = Color(1, 0.8, 0.32)
	gold.metallic = 0.85
	gold.roughness = 0.3
	var necklace_mesh := TorusMesh.new()
	necklace_mesh.inner_radius = 0.1
	necklace_mesh.outer_radius = 0.125
	necklace_mesh.material = gold
	var necklace := MeshInstance3D.new()
	necklace.mesh = necklace_mesh
	add_child(necklace)
	model.attach(necklace, "UpperChest", Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-25)), Vector3(0, 0.17, 0.04)))
	var sash_mat := StandardMaterial3D.new()
	sash_mat.albedo_color = Color(0.75, 0.1, 0.12)
	var sash_mesh := BoxMesh.new()
	sash_mesh.size = Vector3(0.11, 0.6, 0.03)
	sash_mesh.material = sash_mat
	var sash := MeshInstance3D.new()
	sash.mesh = sash_mesh
	add_child(sash)
	model.attach(sash, "Chest", Transform3D(Basis(Vector3.BACK, deg_to_rad(38)), Vector3(0, 0.1, 0.13)))


## A recurved longbow (curved limbs, gold grip) with its string.
func _build_bow_mesh() -> ArrayMesh:
	var limb: Array[Vector3] = []
	for k in 11:
		var t := k / 10.0 * 2.0 - 1.0  # -1 .. 1 along the bow
		var y := t * 0.72
		var z := -0.16 * (1.0 - t * t) + 0.06 * pow(absf(t), 6.0)  # bend, with recurved tips
		limb.append(Vector3(0, y, z))
	var wood := SurfaceTool.new()
	wood.begin(Mesh.PRIMITIVE_TRIANGLES)
	TreeFactory._tube(wood, limb, 0.028, 0.02, 6)
	wood.generate_normals()
	var mesh := ArrayMesh.new()
	wood.commit(mesh)
	var wood_mat := StandardMaterial3D.new()
	wood_mat.albedo_color = Color(0.42, 0.24, 0.1)
	wood_mat.roughness = 0.6
	mesh.surface_set_material(0, wood_mat)
	var string := SurfaceTool.new()
	string.begin(Mesh.PRIMITIVE_TRIANGLES)
	TreeFactory._tube(string, [limb[0], limb[10]] as Array[Vector3], 0.004, 0.004, 4)
	string.generate_normals()
	string.commit(mesh)
	var string_mat := StandardMaterial3D.new()
	string_mat.albedo_color = Color(0.9, 0.85, 0.7)
	mesh.surface_set_material(1, string_mat)
	var grip := SurfaceTool.new()
	grip.begin(Mesh.PRIMITIVE_TRIANGLES)
	TreeFactory._tube(grip, [limb[4], limb[5], limb[6]] as Array[Vector3], 0.036, 0.036, 6)
	grip.generate_normals()
	grip.commit(mesh)
	var gold := StandardMaterial3D.new()
	gold.albedo_color = Color(1, 0.78, 0.3)
	gold.metallic = 0.85
	gold.roughness = 0.3
	mesh.surface_set_material(2, gold)
	return mesh


## Gold crossguard and grip at the handle end of a sword mesh.
func _add_sword_hilt(sword: Node3D) -> void:
	var gold := StandardMaterial3D.new()
	gold.albedo_color = Color(1, 0.78, 0.3)
	gold.metallic = 0.85
	gold.roughness = 0.3
	var guard := MeshInstance3D.new()
	var guard_mesh := BoxMesh.new()
	guard_mesh.size = Vector3(0.22, 0.04, 0.05)
	guard_mesh.material = gold
	guard.mesh = guard_mesh
	guard.position = Vector3(0, 0, 0.48)
	sword.add_child(guard)
	var handle := MeshInstance3D.new()
	var handle_mesh := CylinderMesh.new()
	handle_mesh.top_radius = 0.022
	handle_mesh.bottom_radius = 0.022
	handle_mesh.height = 0.2
	handle_mesh.material = gold
	handle.mesh = handle_mesh
	handle.rotation.x = PI / 2.0
	handle.position = Vector3(0, 0, 0.6)
	sword.add_child(handle)


## The sword is drawn only for sword moves and takedowns; otherwise sheathed.
func _set_sword_drawn(drawn: bool) -> void:
	if _hand_sword:
		_hand_sword.visible = drawn
	if _hip_sword:
		_hip_sword.visible = not drawn


## Play an action animation fitted to `duration`, holding off locomotion meanwhile.
func _act(animation: String, duration: float, lock: float = -1.0) -> void:
	if model == null:
		return
	model.play_fit(animation, duration)
	_anim_lock = duration if lock < 0.0 else lock


func is_dead() -> bool:
	return state == State.DEAD


func is_invulnerable() -> bool:
	return _invuln_left > 0.0 or state in [State.DEAD, State.TAKEDOWN, State.ASTRA]


func aim_point() -> Vector3:
	return global_position + Vector3.UP * 1.2


## Place Rama somewhere (checkpoint) without the camera or interpolation lagging.
## He's set onto the ground at the next physics step (the terrain is uneven).
func teleport(pos: Vector3, face: Vector3 = Vector3.FORWARD) -> void:
	_snap_to_ground = true
	global_position = pos
	velocity = Vector3.ZERO
	facing = face.normalized()
	visual.rotation.y = Combat.yaw_for(facing)
	reset_physics_interpolation()


func _physics_process(delta: float) -> void:
	if _snap_to_ground:
		_snap_to_ground = false
		global_position.y = Combat.ground_height(get_world_3d(), global_position, global_position.y) + 0.05
		velocity.y = 0.0
		reset_physics_interpolation()
	_state_time += delta
	_invuln_left = maxf(_invuln_left - delta, 0.0)
	_bow_cooldown_left = maxf(_bow_cooldown_left - delta, 0.0)
	_read_buffered_input(delta)
	_update_targets(delta)

	if not is_on_floor():
		velocity.y -= gravity * delta

	match state:
		State.MOVE:
			_state_move(delta)
		State.ATTACK:
			_state_attack(delta)
		State.DODGE:
			_state_dodge()
		State.HURT:
			_decelerate(delta, 20.0)
			if _state_time >= 0.35:
				state = State.MOVE
		State.TAKEDOWN:
			_state_takedown(delta)
		State.ASTRA:
			_state_astra(delta)
		State.DEAD:
			_decelerate(delta, 20.0)

	move_and_slide()
	_update_visual(delta)


# --- States -----------------------------------------------------------------

func _state_move(delta: float) -> void:
	var dir := _move_input()
	is_aiming = Input.is_action_pressed("aim")
	var speed := sneak_speed if is_sneaking else move_speed
	if is_aiming:
		speed = aim_move_speed
	if bow_charge >= 0.0:
		speed = 0.0  # Rama plants his feet to draw the bow
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	horizontal = horizontal.move_toward(dir * speed, acceleration * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z

	if is_aiming:
		# Face where the camera looks; left click / RT draws, release fires.
		var rig := _rig()
		if rig:
			facing = rig.forward_flat()
		visual.rotation.y = Combat.yaw_for(facing)
		var firing := Input.is_action_pressed("attack_light") or Input.is_action_pressed("bow")
		if firing and bow_charge < 0.0 and _bow_cooldown_left <= 0.0:
			bow_charge = 0.0
			_set_bow_pose(true)
		if _buffered == "light":
			_consume_buffer()  # left click is the bow while aiming, not the blades
	elif bow_charge >= 0.0:
		_cancel_bow()  # let go of aim: lower the bow
	elif dir.length() > 0.1:
		facing = dir.normalized()
	if bow_charge >= 0.0:
		_update_bow(delta)

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity
	if Input.is_action_just_pressed("sneak"):
		is_sneaking = not is_sneaking
	if Input.is_action_just_pressed("chakra"):
		_throw_chakra()
	if Input.is_action_just_pressed("astra") and astra >= astra_max:
		_start_astra()
		return
	if Input.is_action_just_pressed("interact") and takedown_candidate:
		_start_takedown(takedown_candidate)
		return

	match _consume_buffer():
		"dodge":
			_start_dodge()
		"light":
			if takedown_candidate:
				_start_takedown(takedown_candidate)
			else:
				_light_count = 0
				_start_attack("jab")
		"heavy":
			_light_count = 0
			_start_attack("heavy")


func _state_attack(delta: float) -> void:
	# Hover a little when attacking in the air, so air combos feel good.
	if not is_on_floor():
		velocity.y = maxf(velocity.y, -1.5)

	if _phase == Phase.STARTUP:
		var lunge: float = _attack["lunge"]
		if is_instance_valid(_lunge_target):
			var gap := _lunge_target.global_position - global_position
			gap.y = 0.0
			if gap.length() < 1.3:  # already close enough, don't run into them
				lunge = 0.0
		velocity.x = facing.x * lunge
		velocity.z = facing.z * lunge
		if _state_time >= float(_attack["startup"]):
			_do_hit()
			_phase = Phase.RECOVERY
			_state_time = 0.0
			_tween_to_rest(float(_attack["recovery"]) * 0.8)
		return

	_decelerate(delta, 30.0)
	var recovery: float = _attack["recovery"]
	if _state_time >= recovery * chain_point and _buffered != "":
		if _buffered == "dodge":
			_consume_buffer()
			_start_dodge()
			return
		# Strings continue only from the first two punches.
		var in_light_string := current_attack in ["jab", "cross"]
		if _buffered == "light" and in_light_string:
			_consume_buffer()
			_start_attack(LIGHT_STRING[_light_count])
			return
		if _buffered == "heavy" and in_light_string:
			_consume_buffer()
			_start_attack(HEAVY_AFTER[_light_count])
			return
	if _state_time >= recovery:
		state = State.MOVE
		current_attack = ""
		_light_count = 0


func _state_dodge() -> void:
	var t := clampf(_state_time / dodge_time, 0.0, 1.0)
	var speed := lerpf(dodge_speed, dodge_speed * 0.35, t * t)
	velocity.x = _dodge_dir.x * speed
	velocity.z = _dodge_dir.z * speed
	if _state_time >= dodge_time:
		collision_mask = Combat.LAYER_WORLD | Combat.LAYER_ENEMY
		body_pivot.rotation = Vector3.ZERO
		state = State.MOVE


func _state_takedown(_delta: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	if not _takedown_struck and _state_time >= 0.3:
		_takedown_struck = true
		if is_instance_valid(_takedown_victim) and not _takedown_victim.is_dead():
			_takedown_victim.take_damage(9999.0, global_position, 0.0, "takedown")
			FX.hit_spark(_takedown_victim.aim_point())
		FX.hitstop(0.16)
		FX.add_trauma(0.3)
	if _state_time >= 0.65:
		state = State.MOVE
		_tween_to_rest(0.2)


func _state_astra(_delta: float) -> void:
	velocity = Vector3.ZERO
	if not _astra_fired and _state_time >= 0.55:
		_astra_fired = true
		FX.divine_blast(global_position, astra_radius)
		Combat.damage_in_radius(get_world_3d(), global_position + Vector3.UP, astra_radius,
			Combat.LAYER_ENEMY | Combat.LAYER_WORLD, astra_damage, 12.0, "astra", [get_rid()])
		FX.hitstop(0.2)
		FX.add_trauma(0.8)
	if _state_time >= 0.9:
		state = State.MOVE
		_tween_to_rest(0.25)


# --- Actions ----------------------------------------------------------------

func _start_attack(attack_name: String) -> void:
	_cancel_bow()
	is_sneaking = false
	state = State.ATTACK
	_phase = Phase.STARTUP
	_state_time = 0.0
	current_attack = attack_name
	_attack = ATTACKS[attack_name]
	if attack_name in LIGHT_STRING:
		_light_count += 1

	# Soft lock-on: turn toward the best nearby enemy, else toward the stick.
	_lunge_target = _find_melee_target()
	if _lunge_target:
		facing = Combat.flat_direction(global_position, _lunge_target.global_position, facing)
	else:
		var dir := _move_input()
		if dir.length() > 0.2:
			facing = dir.normalized()
	visual.rotation.y = Combat.yaw_for(facing)
	_set_sword_drawn(bool(_attack["sword"]))
	_act(String(_attack["anim"]), float(_attack["anim_time"]), float(_attack["startup"]) + float(_attack["recovery"]))


func _do_hit() -> void:
	var center := global_position + Vector3.UP + facing * float(_attack["reach"])
	var mask := Combat.LAYER_ENEMY | Combat.LAYER_WORLD
	var hits := Combat.sphere_query(get_world_3d(), center, float(_attack["radius"]), mask, [get_rid()])
	var landed := false
	var killed := false
	for target in hits:
		if target.has_method("take_damage") and target.take_damage(float(_attack["damage"]), global_position, float(_attack["knockback"]), String(_attack["kind"])):
			landed = true
			FX.hit_spark(Combat.aim_point(target as Node3D))
			if target.has_method("is_dead") and target.is_dead():
				killed = true
	var shockwave: bool = _attack.get("shockwave", false)
	if shockwave:
		FX.shockwave(global_position, float(_attack["radius"]))
	if landed:
		# A kill freezes a touch longer, to make it land.
		FX.hitstop(float(_attack["hitstop"]) + (0.06 if killed else 0.0))
		FX.add_trauma(float(_attack["shake"]))
	elif shockwave:
		FX.add_trauma(float(_attack["shake"]) * 0.4)


func _start_dodge() -> void:
	_cancel_bow()
	is_sneaking = false
	state = State.DODGE
	_state_time = 0.0
	var dir := _move_input()
	_dodge_dir = dir.normalized() if dir.length() > 0.1 else facing
	facing = _dodge_dir
	visual.rotation.y = Combat.yaw_for(facing)
	_invuln_left = maxf(_invuln_left, dodge_iframes)
	collision_mask = Combat.LAYER_WORLD  # roll through enemies
	_act("Roll", dodge_time * 1.4, dodge_time)
	_reset_pose()
	_pose_tween = _new_tween()
	_pose_tween.tween_property(body_pivot, "rotation:x", -TAU, dodge_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _start_takedown(victim: Enemy) -> void:
	_cancel_bow()
	_consume_buffer()
	state = State.TAKEDOWN
	_state_time = 0.0
	_takedown_struck = false
	_takedown_victim = victim
	victim.receive_takedown()
	_set_sword_drawn(true)
	_act("Stab1", 0.65)
	# Step in right behind them.
	var behind := victim.global_position - victim.facing() * 0.9
	behind.y = global_position.y
	global_position = behind
	facing = victim.facing()
	visual.rotation.y = Combat.yaw_for(facing)
	_reset_pose()
	_pose_tween = _new_tween().set_parallel(true)
	_pose_tween.tween_property(blade_r, "rotation", _deg(100, -10, 0), 0.25)
	_pose_tween.tween_property(blade_l, "rotation", _deg(100, 10, 0), 0.25)
	_pose_tween.chain().tween_property(blade_r, "rotation", _deg(-30, 10, 0), 0.06)
	_pose_tween.parallel().tween_property(blade_l, "rotation", _deg(-30, -10, 0), 0.06)


func _start_astra() -> void:
	_cancel_bow()
	is_sneaking = false
	state = State.ASTRA
	_state_time = 0.0
	_astra_fired = false
	astra = 0.0
	_act("SlashUppercut", 0.9)
	_reset_pose()
	_pose_tween = _new_tween()
	_pose_tween.tween_property(body_pivot, "position:y", 1.6, 0.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_pose_tween.parallel().tween_property(blade_r, "rotation", _deg(170, 0, 0), 0.5)
	_pose_tween.parallel().tween_property(blade_l, "rotation", _deg(170, 0, 0), 0.5)
	_pose_tween.tween_property(body_pivot, "position:y", 0.9, 0.12)


func _update_bow(delta: float) -> void:
	bow_charge = minf(bow_charge + delta / charge_time, 1.0)
	if not (Input.is_action_pressed("attack_light") or Input.is_action_pressed("bow")):
		_fire_arrow(bow_charge >= 1.0)


func _rig() -> CameraRig:
	return get_tree().get_first_node_in_group("camera_rig") as CameraRig


## Where an arrow or chakra should go: the crosshair, nudged onto an enemy
## that's close to it (gentle aim assist).
func crosshair_target() -> Vector3:
	var rig := _rig()
	if rig == null:
		return global_position + Vector3.UP * 1.3 + facing * 30.0
	var assist := aim_assist_target()
	if assist:
		return Combat.aim_point(assist)
	return rig.crosshair_point(lock_range * 2.0, [get_rid()])


## An enemy or target near the middle of the screen, if any.
func aim_assist_target() -> Node3D:
	var rig := _rig()
	if rig == null:
		return null
	var cam := rig.camera
	var center := get_viewport().get_visible_rect().size * 0.5
	var radius := get_viewport().get_visible_rect().size.y * aim_assist_screen
	var best: Node3D = null
	var best_d := radius
	for target in _ranged_candidates():
		var point := Combat.aim_point(target)
		if cam.is_position_behind(point):
			continue
		var d := cam.unproject_position(point).distance_to(center)
		if d < best_d:
			best_d = d
			best = target
	return best


func _fire_arrow(charged: bool) -> void:
	bow_charge = -1.0
	_bow_cooldown_left = bow_cooldown
	_set_bow_pose(false)
	if arrow_scene == null:
		return
	var start := global_position + Vector3.UP * 1.35 + facing * 0.5
	var dir := (crosshair_target() - start).normalized()
	_act("ThrowLTopOnly", 0.4, 0.2)
	var arrow := arrow_scene.instantiate() as Projectile
	if charged:
		arrow.speed = 55.0
		arrow.damage = 35.0
		arrow.knockback = 6.0
		arrow.kind = "charged"
		arrow.pierce = true
	get_tree().current_scene.add_child(arrow)
	arrow.launch(start, dir, self)
	if charged:
		FX.add_trauma(0.15)


func _cancel_bow() -> void:
	if bow_charge >= 0.0:
		bow_charge = -1.0
		_set_bow_pose(false)


func _throw_chakra() -> void:
	if not has_chakra or not chakra_ready or chakra_scene == null:
		return
	chakra_ready = false
	var start := global_position + Vector3.UP * 1.3 + facing * 0.6
	# Homes in on: the enemy under the crosshair while aiming, otherwise the
	# best enemy in front of Rama. With nothing to hunt it flies straight.
	var homing: Node3D = aim_assist_target() if is_aiming else null
	if homing == null and not is_aiming:
		homing = current_target if Combat.is_alive_target(current_target) else _best_ranged_target()
	# Only hunts things within its short reach.
	if homing and homing.global_position.distance_to(global_position) > chakra_range:
		homing = null
	var target_point := crosshair_target() if is_aiming else start + facing * chakra_range
	if start.distance_to(target_point) > chakra_range:
		target_point = start + (target_point - start).normalized() * chakra_range
	if homing:
		target_point = Combat.aim_point(homing)
		if not is_aiming:
			facing = Combat.flat_direction(global_position, homing.global_position, facing)
			visual.rotation.y = Combat.yaw_for(facing)
	var chakra := chakra_scene.instantiate() as ChakraProjectile
	get_tree().current_scene.add_child(chakra)
	chakra.launch(self, start, target_point, homing)
	chakra.caught.connect(func() -> void: chakra_ready = true)
	_act("ThrowR", 0.55, 0.35)
	# Quick throwing flick of the right arm.
	_kill_pose_tween()
	_pose_tween = _new_tween()
	_pose_tween.tween_property(blade_r, "rotation", _deg(-10, -100, 0), 0.06)
	_pose_tween.tween_property(blade_r, "rotation", _deg(-10, 60, 0), 0.08)
	_pose_tween.tween_property(blade_r, "rotation", _rest_r, 0.25)


func unlock_chakra() -> void:
	has_chakra = true
	chakra_ready = true
	Game.has_chakra = true
	chakra_unlocked.emit()


func add_astra(amount: float) -> void:
	if state == State.DEAD:
		return
	var was_full := astra >= astra_max
	astra = minf(astra + amount, astra_max)
	if not was_full and astra >= astra_max:
		astra_ready.emit()


func take_damage(amount: float, from_position: Vector3, knockback: float, _kind: String = "") -> bool:
	if is_invulnerable():
		return false
	health = maxf(health - amount, 0.0)
	health_changed.emit(health, max_health)
	FX.flash(visual, Color(1, 0.15, 0.1, 0.75), 0.12)
	FX.add_trauma(0.45)
	FX.hitstop(0.07)
	_cancel_bow()
	is_sneaking = false
	if health <= 0.0:
		_die()
		return true
	state = State.HURT
	_state_time = 0.0
	_invuln_left = 0.5
	var away := Combat.flat_direction(from_position, global_position, -facing)
	velocity.x = away.x * knockback
	velocity.z = away.z * knockback
	_reset_pose()
	_act("Hurt1" if randf() < 0.5 else "Hurt2", 0.4)
	return true


func heal(amount: float) -> void:
	if state == State.DEAD:
		return
	health = minf(health + amount, max_health)
	health_changed.emit(health, max_health)


func _die() -> void:
	state = State.DEAD
	_reset_pose()
	if model:
		model.play("Die1", 1.0, 0.1, true)
		_anim_lock = 999.0
	_pose_tween = _new_tween()
	_pose_tween.tween_property(body_pivot, "rotation:x", deg_to_rad(80), 0.5).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	died.emit()


# --- Targeting --------------------------------------------------------------

func _update_targets(delta: float) -> void:
	# Unaware enemy right behind? Offer a takedown.
	takedown_candidate = null
	if state == State.MOVE:
		var best_dist := INF
		for node in get_tree().get_nodes_in_group("enemies"):
			var enemy := node as Enemy
			if enemy and enemy.can_be_taken_down(self):
				var d := enemy.global_position.distance_to(global_position)
				if d < best_dist:
					best_dist = d
					takedown_candidate = enemy

	if Input.is_action_just_pressed("switch_target"):
		_cycle_target()
		_target_refresh_left = 1.0
	_target_refresh_left -= delta
	if not _target_still_good(current_target):
		current_target = null
	if current_target == null or _target_refresh_left <= 0.0:
		_target_refresh_left = 0.15 if current_target == null else 0.5
		if current_target == null or bow_charge < 0.0:
			current_target = _best_ranged_target()


func _target_still_good(target: Node3D) -> bool:
	if not Combat.is_alive_target(target):
		return false
	return target.global_position.distance_to(global_position) < lock_range * 1.2


func _ranged_candidates() -> Array[Node3D]:
	var out: Array[Node3D] = []
	var eye := global_position + Vector3.UP * 1.4
	for node in get_tree().get_nodes_in_group("targetable"):
		var target := node as Node3D
		if not Combat.is_alive_target(target):
			continue
		var point := Combat.aim_point(target)
		if point.distance_to(eye) > lock_range:
			continue
		if Combat.line_of_sight(get_world_3d(), eye, point):
			out.append(target)
	return out


func _reference_direction() -> Vector3:
	var dir := _move_input()
	if dir.length() > 0.2:
		return dir.normalized()
	var cam := get_viewport().get_camera_3d()
	if cam and bow_charge < 0.0:
		var forward := -cam.global_basis.z
		forward.y = 0.0
		if forward.length_squared() > 0.001:
			return forward.normalized().lerp(facing, 0.5).normalized()
	return facing


func _best_ranged_target() -> Node3D:
	var reference := _reference_direction()
	var best: Node3D = null
	var best_score := -INF
	for target in _ranged_candidates():
		var to_target := target.global_position - global_position
		to_target.y = 0.0
		var dist := to_target.length()
		var alignment := reference.dot(to_target.normalized()) if dist > 0.01 else 1.0
		if alignment < 0.4 and dist > 4.0:
			continue
		var score := alignment * 2.0 - dist / lock_range
		if target is Enemy:
			score += 0.3  # prefer enemies over props
		if score > best_score:
			best_score = score
			best = target
	return best


func _cycle_target() -> void:
	var candidates := _ranged_candidates()
	if candidates.is_empty():
		current_target = null
		return
	var cam := get_viewport().get_camera_3d()
	var right := cam.global_basis.x if cam else Vector3.RIGHT
	# Sort left-to-right on screen, then step to the next one.
	candidates.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		return right.dot(a.global_position - global_position) < right.dot(b.global_position - global_position))
	var index := candidates.find(current_target)
	current_target = candidates[(index + 1) % candidates.size()]


func _find_melee_target() -> Node3D:
	var input := _move_input()
	var reference := input.normalized() if input.length() > 0.2 else facing
	var best: Node3D = null
	var best_score := -INF
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as Node3D
		if enemy == null or (enemy.has_method("is_dead") and enemy.is_dead()):
			continue
		var to_enemy := enemy.global_position - global_position
		to_enemy.y = 0.0
		var dist := to_enemy.length()
		if dist > melee_target_range or dist < 0.01:
			continue
		var alignment := reference.dot(to_enemy / dist)
		if alignment < -0.2 and dist > 1.8:
			continue  # behind Rama and not right on top of him
		var score := alignment * 2.0 - dist * 0.35
		if score > best_score:
			best_score = score
			best = enemy
	return best


# --- Helpers ----------------------------------------------------------------

func _read_buffered_input(delta: float) -> void:
	if Input.is_action_just_pressed("dodge"):
		_set_buffer("dodge")
	elif Input.is_action_just_pressed("attack_heavy"):
		_set_buffer("heavy")
	elif Input.is_action_just_pressed("attack_light"):
		_set_buffer("light")
	elif _buffer_left > 0.0:
		_buffer_left -= delta
		if _buffer_left <= 0.0:
			_buffered = ""


func _set_buffer(action: String) -> void:
	_buffered = action
	_buffer_left = input_buffer_time


func _consume_buffer() -> String:
	var action := _buffered
	_buffered = ""
	_buffer_left = 0.0
	return action


func _decelerate(delta: float, rate: float) -> void:
	var horizontal := Vector3(velocity.x, 0.0, velocity.z).move_toward(Vector3.ZERO, rate * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z


func _update_visual(delta: float) -> void:
	if state != State.ATTACK and state != State.TAKEDOWN and _hand_sword and _hand_sword.visible:
		_set_sword_drawn(false)
	if state != State.ATTACK:
		current_attack = ""
	if model:
		_update_animation(delta)
	if state != State.MOVE:
		is_aiming = false
	if state == State.MOVE and bow_charge < 0.0 and not is_aiming:
		visual.rotation.y = lerp_angle(visual.rotation.y, Combat.yaw_for(facing), 1.0 - exp(-turn_speed * delta))
	# Crouch while sneaking.
	var crouch := 0.78 if is_sneaking and state == State.MOVE else 1.0
	visual.scale = visual.scale.lerp(Vector3(1.0, crouch, 1.0), 1.0 - exp(-14.0 * delta))
	# Blink while invulnerable after being hit.
	visual.visible = not (state == State.MOVE and _invuln_left > 0.0 and int(_invuln_left * 20.0) % 2 == 1)


## Picks idle/run/fall/aim animations while Rama isn't doing an action.
func _update_animation(delta: float) -> void:
	_anim_lock -= delta
	if _anim_lock > 0.0 or state != State.MOVE:
		return
	var speed := Vector2(velocity.x, velocity.z).length()
	if bow_charge >= 0.0 or is_aiming:
		model.play("Guarding", 1.0, 0.1)
	elif not is_on_floor():
		model.play("LightFalling", 1.0, 0.15)
	elif speed > 0.4:
		if is_sneaking or speed < 3.5:
			model.play("LightWalking", clampf(speed / 2.0, 0.6, 1.4), 0.15)
		else:
			model.play("LightRunning", clampf(speed / 6.0, 0.7, 1.3), 0.12)
	else:
		model.play("LightIdle", 1.0, 0.2)


func _set_bow_pose(aiming: bool) -> void:
	if model:
		return  # the bow stays on Rama's back until there's a proper bow animation
	var tween := _new_tween().set_parallel(true)
	tween.tween_property(bow_mesh, "position", _bow_aim_pos if aiming else _bow_back_pos, 0.1)
	tween.tween_property(bow_mesh, "rotation", _bow_aim_rot if aiming else _bow_back_rot, 0.1)


func _tween_to_rest(duration: float) -> void:
	_kill_pose_tween()
	_pose_tween = _new_tween().set_parallel(true)
	_pose_tween.tween_property(blade_r, "rotation", _rest_r, duration)
	_pose_tween.tween_property(blade_l, "rotation", _rest_l, duration)
	_pose_tween.tween_property(body_pivot, "rotation", Vector3.ZERO, duration)
	_pose_tween.tween_property(body_pivot, "position:y", 0.9, duration)


func _reset_pose() -> void:
	_kill_pose_tween()
	blade_r.rotation = _rest_r
	blade_l.rotation = _rest_l
	body_pivot.rotation = Vector3.ZERO
	body_pivot.position.y = 0.9


func _kill_pose_tween() -> void:
	if _pose_tween and _pose_tween.is_valid():
		_pose_tween.kill()


func _new_tween() -> Tween:
	# Physics-step tweens keep the animated parts in sync with physics interpolation.
	return create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)


func _deg(x: float, y: float, z: float) -> Vector3:
	return Vector3(deg_to_rad(x), deg_to_rad(y), deg_to_rad(z))


## Stick/WASD input turned into a world direction relative to the active camera.
func _move_input() -> Vector3:
	var raw := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if raw == Vector2.ZERO:
		return Vector3.ZERO
	var forward := Vector3.FORWARD
	var right := Vector3.RIGHT
	var cam := get_viewport().get_camera_3d()
	if cam:
		forward = -cam.global_basis.z
		forward.y = 0.0
		if forward.length_squared() < 0.001:
			forward = cam.global_basis.y  # camera looking straight down
			forward.y = 0.0
		right = cam.global_basis.x
		right.y = 0.0
		forward = forward.normalized()
		right = right.normalized()
	return (right * raw.x - forward * raw.y).limit_length(1.0)
