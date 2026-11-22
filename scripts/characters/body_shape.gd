class_name BodyShape
extends SkeletonModifier3D
## Bulks up the mannequin after each animation frame: scales the upper chest
## (which carries the shoulders and arms) for a broad, powerful build, then
## scales the neck back down so the head stays normal-sized.
## Uniform scales only, so nothing shears when the body twists.

## 1.0 = mannequin default. ~1.1 heroic, ~1.2 hulking.
@export var upper_body := 1.12
@export var arms := 1.0

var _upper_chest := -1
var _neck := -1
var _upper_arms: Array[int] = []
var _lower_arms: Array[int] = []


func _ready() -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	_upper_chest = skeleton.find_bone("UpperChest")
	_neck = skeleton.find_bone("Neck")
	for side in ["Left", "Right"]:
		_upper_arms.append(skeleton.find_bone(side + "UpperArm"))
		_lower_arms.append(skeleton.find_bone(side + "LowerArm"))


func _process_modification_with_delta(_delta: float) -> void:
	_apply()


func _process_modification() -> void:
	_apply()


func _apply() -> void:
	var skeleton := get_skeleton()
	if skeleton == null or _upper_chest < 0:
		return
	skeleton.set_bone_pose_scale(_upper_chest, Vector3.ONE * upper_body)
	if _neck >= 0:
		skeleton.set_bone_pose_scale(_neck, Vector3.ONE / upper_body)
	# Optional extra arm mass (upper arm bigger, forearm/hand back to normal).
	for i in _upper_arms.size():
		if _upper_arms[i] >= 0:
			skeleton.set_bone_pose_scale(_upper_arms[i], Vector3.ONE * arms)
		if _lower_arms[i] >= 0:
			skeleton.set_bone_pose_scale(_lower_arms[i], Vector3.ONE / arms)
