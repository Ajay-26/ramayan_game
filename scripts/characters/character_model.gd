class_name CharacterModel
extends Node3D
## Animated humanoid body: the CC0 mannequin from Cat's Godot 4 Souls-like
## Template, driven by its 120-animation library (assets/characters/MeleeLib.res).
## Gameplay scripts call play("LightRunning") etc. and attach weapons to bones.
## Tints let the same body read as Rama (blue skin, saffron cloth) or a
## rakshasa (dark red skin), until custom character models replace it.

const MODEL := preload("res://assets/characters/mannyquin.glb")
const LIBRARY := preload("res://assets/characters/MeleeLib.res")
const LIB_NAME := "melee"
## Average color of the mannequin's skin texture, used to paint "bare skin".
const SKIN_AVERAGE := Color(0.88, 0.656, 0.621)
const MUSCLE_SHADER := preload("res://shaders/muscle_skin.gdshader")
## Silhouette rim light on every body material (see _add_rim).
const RIM := 0.55
const RIM_TINT := 0.35

@export var skin_tint := Color(1, 1, 1)
@export var cloth_tint := Color(1, 1, 1)
@export var hair_tint := Color(0.1, 0.08, 0.08)
## Paint the mannequin's bodysuit the same color as the skin (bare-chested look).
@export var bare_skin := false
## Waist-cloth (dhoti / loincloth) color; fully transparent = none.
## Upper-body bulk (1.0 = mannequin default) and extra upper-arm mass.
@export var upper_body := 1.12
@export var arm_mass := 1.0
## Strength of the painted muscle lines on bare skin.
@export var definition := 1.0
@export var waist_cloth_color := Color(0, 0, 0, 0)
@export var waist_cloth_length := 0.55
@export var gold_belt := false
@export var show_armor := false
@export var show_helm := false
@export var show_hair := true
## Seconds to cross-fade between animations.
@export var default_blend := 0.12
@export var start_animation := "LightIdle"

## Bone-space mount points measured from Cat's template rig.
const HAND_R := "Transform3D(-4.37114e-08, 1, -4.37114e-08, 0, -4.37114e-08, -1, -1, -4.37114e-08, 1.91069e-15, 0, 0.085, 0.025)"
const HAND_L := "Transform3D(-4.37114e-08, -1, 0, 1, -4.37114e-08, 0, 0, 0, 1, 0, 0.095, 0.02)"

var anim: AnimationPlayer
var skeleton: Skeleton3D
var _current := ""


func _ready() -> void:
	var body := MODEL.instantiate() as Node3D
	body.rotation.y = PI  # the model faces +Z; our characters face -Z
	add_child(body)
	skeleton = body.find_child("GeneralSkeleton", true, false) as Skeleton3D
	anim = body.find_child("AnimationPlayer", true, false) as AnimationPlayer
	anim.add_animation_library(LIB_NAME, LIBRARY)
	var shape := BodyShape.new()
	shape.upper_body = upper_body
	shape.arms = arm_mass
	skeleton.add_child(shape)
	_apply_looks()
	_add_clothes()
	play(start_animation)


## Cross-fade to an animation from the library. Calling it again with the same
## name just updates the speed, unless restart is true.
func play(animation: String, speed: float = 1.0, blend: float = -1.0, restart: bool = false) -> void:
	if anim == null:
		return
	var full := LIB_NAME + "/" + animation
	if full == _current and not restart:
		anim.speed_scale = speed
		return
	_current = full
	anim.speed_scale = speed
	anim.play(full, default_blend if blend < 0.0 else blend)
	if restart:
		anim.seek(0.0, true)


## Play so that the whole animation fits into `duration` seconds.
func play_fit(animation: String, duration: float, blend: float = 0.06) -> void:
	var length := animation_length(animation)
	play(animation, length / maxf(duration, 0.05), blend, true)


func animation_length(animation: String) -> float:
	var full := LIB_NAME + "/" + animation
	return anim.get_animation(full).length if anim and anim.has_animation(full) else 1.0


func current() -> String:
	return _current.trim_prefix(LIB_NAME + "/")


## Parent a node to a bone so it follows the animation (weapons, crowns...).
func attach(node: Node3D, bone: String, offset := Transform3D.IDENTITY) -> BoneAttachment3D:
	var attachment := BoneAttachment3D.new()
	attachment.bone_name = bone
	skeleton.add_child(attachment)
	if node.get_parent():
		node.get_parent().remove_child(node)
	attachment.add_child(node)
	node.transform = offset
	return attachment


## Put a weapon that points along -Z (club, blade, maul) into a hand.
## `grip` slides it along its length so the handle sits in the fist.
func attach_weapon(node: Node3D, right_hand: bool = true, grip: float = 0.3) -> BoneAttachment3D:
	var pivot: Transform3D = str_to_var(HAND_R if right_hand else HAND_L)
	var fix := Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3.ZERO)
	return attach(node, "RightHand" if right_hand else "LeftHand", pivot * fix * Transform3D(Basis(), Vector3(0, 0, -grip)))


func _apply_looks() -> void:
	for child in skeleton.get_children():
		var mesh := child as MeshInstance3D
		if mesh == null:
			continue
		match String(mesh.name):
			"Armor":
				mesh.visible = show_armor
			"Helm":
				mesh.visible = show_helm
			"Hair", "Lashes":
				mesh.visible = show_hair
				_tint(mesh, 0, hair_tint)
			"MannyQuinn":
				_tint(mesh, 0, skin_tint)
				if mesh.mesh.get_surface_count() > 1:
					if bare_skin:
						var muscles := ShaderMaterial.new()
						muscles.shader = MUSCLE_SHADER
						muscles.set_shader_parameter("skin_color", SKIN_AVERAGE * skin_tint)
						muscles.set_shader_parameter("definition", definition)
						muscles.set_shader_parameter("rim_amount", RIM)
						muscles.set_shader_parameter("rim_tint_amount", RIM_TINT)
						mesh.set_surface_override_material(1, muscles)
					else:
						_tint(mesh, 1, cloth_tint, true)


func _add_clothes() -> void:
	if waist_cloth_color.a > 0.0:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = waist_cloth_color
		mat.roughness = 0.85
		var cloth := CylinderMesh.new()
		cloth.top_radius = 0.17
		cloth.bottom_radius = 0.26
		cloth.height = waist_cloth_length
		cloth.material = mat
		var mesh := MeshInstance3D.new()
		mesh.mesh = cloth
		mesh.name = "WaistCloth"
		add_child(mesh)
		attach(mesh, "Hips", Transform3D(Basis(), Vector3(0, 0.02 - waist_cloth_length * 0.5, 0)))
	if gold_belt:
		var gold := StandardMaterial3D.new()
		gold.albedo_color = Color(1, 0.78, 0.3)
		gold.metallic = 0.85
		gold.roughness = 0.3
		var ring := TorusMesh.new()
		ring.inner_radius = 0.15
		ring.outer_radius = 0.19
		ring.material = gold
		var belt := MeshInstance3D.new()
		belt.mesh = ring
		belt.name = "Belt"
		add_child(belt)
		attach(belt, "Hips", Transform3D(Basis(), Vector3(0, 0.03, 0)))


## Multiply the existing color by `color`, or (replace) use `color` outright.
func _tint(mesh: MeshInstance3D, surface: int, color: Color, replace: bool = false) -> void:
	var source := mesh.get_active_material(surface) as BaseMaterial3D
	if source == null:
		return
	var mat := source.duplicate() as BaseMaterial3D
	mat.albedo_color = color if replace else source.albedo_color * color
	if replace:
		mat.albedo_texture = null
	_add_rim(mat)
	mesh.set_surface_override_material(surface, mat)


## A bright rim along the silhouette, so figures pop out of the dark scenery.
static func _add_rim(mat: BaseMaterial3D) -> void:
	mat.rim_enabled = true
	mat.rim = RIM
	mat.rim_tint = RIM_TINT
