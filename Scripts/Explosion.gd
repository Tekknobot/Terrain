extends Node2D

@export var duration := 0.5
@export var explosion_animation := "explode"  # kept for compatibility
@export var camera_shake_intensity := 5.0

var tile_pos: Vector2i
const SETTINGS_PATH := "user://settings.cfg"

func _ready() -> void:
	# Prefer parent TileMap if spawned under it; otherwise try scene root.
	var tilemap := (get_parent() if get_parent() is TileMap else get_tree().get_current_scene().get_node_or_null("TileMap")) as TileMap
	if tilemap:
		tile_pos = tilemap.local_to_map(tilemap.to_local(global_position))
	else:
		tile_pos = Vector2i.ZERO

	# Absolute Z so it ignores parent Z stacking; order by Y for nice layering.
	z_as_relative = false
	z_index = tile_pos.y + 1000

	# Camera shake (gated by settings)
	if _cfg_get_bool("gameplay", "camera_shake", true):
		var cam := get_viewport().get_camera_2d()
		if cam and cam.has_method("shake") and camera_shake_intensity > 0.0:
			cam.shake(camera_shake_intensity)

func _on_explosion_finished(_anim_name) -> void:
	queue_free()

# --- lightweight config helper ---
func _cfg_get_bool(section: String, key: String, def: bool) -> bool:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH) # OK if missing
	return bool(cfg.get_value(section, key, def))
