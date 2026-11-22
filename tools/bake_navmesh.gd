extends Node
## Bakes the Siddhashrama navigation mesh from its level geometry and saves it,
## so the game doesn't have to bake at load time (slow on the web).
## Run after changing the level layout:
##   Godot --headless --path . res://tools/bake_navmesh.tscn

const LEVEL := "res://scenes/levels/siddhashrama.tscn"
const NAVMESH := "res://scenes/levels/siddhashrama_navmesh.tres"


func _ready() -> void:
	var level: Node = load(LEVEL).instantiate()
	add_child(level)
	# CSG pieces build their geometry on the first frames.
	await get_tree().process_frame
	await get_tree().process_frame
	var region := level.get_node("NavRegion") as NavigationRegion3D
	region.bake_navigation_mesh(false)
	var mesh := region.navigation_mesh
	print("navmesh polygons: ", mesh.get_polygon_count(), "  vertices: ", mesh.vertices.size())
	var err := ResourceSaver.save(mesh, NAVMESH)
	print("saved: ", error_string(err))
	get_tree().quit(0 if err == OK and mesh.get_polygon_count() > 0 else 1)
