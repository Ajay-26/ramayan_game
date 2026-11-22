extends Marker3D
## Where an encounter wave spawns one enemy.

@export var enemy_scene: PackedScene
## For archers placed on ledges: they hold position instead of walking.
@export var stationary := false
