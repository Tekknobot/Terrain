extends Node2D

@export var is_player: bool = true  
@export var unit_type: String = "Soldier"  
var health: int = 100
var max_health: int = 100
var xp: int = 0
var max_xp: int = 100
var movement_range: int = 3  

@onready var health_bar = $HealthUI
@onready var xp_bar = $XPUI

var tile_pos: Vector2i

func _ready():
	var tilemap = get_tree().get_current_scene().get_node("TileMap")
	if tilemap:
		tile_pos = tilemap.local_to_map(global_position)
	update_z_index()
	update_health_bar()
	update_xp_bar()

func set_team(player_team: bool):
	is_player = player_team
	if is_player:
		modulate = Color(1, 1, 1)
	else:
		modulate = Color(1, 110.0/255.0, 1)

func update_z_index():
	z_index = int(position.y)

func _process(delta):
	update_z_index()

### TURN & MOVEMENT HANDLING
func start_turn():
	print(unit_type + " is now active!")
	var tilemap = get_tree().get_current_scene().get_node("TileMap")
	if tilemap:
		tilemap.highlight_movement_range(self)  # Trigger tile highlight
	if is_player:
		print("Player, select a tile to move!")
	else:
		ai_move()

func ai_move():
	var tilemap = get_tree().get_current_scene().get_node("TileMap")
	if tilemap:
		var current_tile = tilemap.local_to_map(global_position)
		var random_offset = Vector2i(randi_range(-movement_range, movement_range), randi_range(-movement_range, movement_range))
		var target_tile = current_tile + random_offset
		if tilemap.is_valid_spawn(target_tile):
			tilemap.move_unit(self, target_tile)

func move_along_path(path: Array):
	if path.is_empty():
		return

	var tween = create_tween()
	var tilemap = get_tree().get_current_scene().get_node("TileMap")
	if tilemap == null:
		print("TileMap not found!")
		return

	var t_size: Vector2 = tilemap.get_tileset().tile_size

	$AnimatedSprite2D.play("move")

	for tile_coord in path:
		var local_pos = tilemap.map_to_local(tile_coord)
		var world_pos = tilemap.to_global(local_pos) + t_size / 2

		tween.tween_property(self, "global_position", world_pos, 0.2)
		tween.tween_callback(Callable(self, "_update_tile_pos").bind(tile_coord))

	await tween.finished	
	
	$AnimatedSprite2D.play("default")

	tilemap.update_astar_grid()
	print("Finished moving along path.")

func _update_tile_pos(new_tile: Vector2i) -> void:
	tile_pos = new_tile


### HEALTH & XP MECHANICS
func take_damage(amount: int):
	health = max(health - amount, 0)
	update_health_bar()
	if health <= 0:
		die()

func gain_xp(amount: int):
	xp = min(xp + amount, max_xp)
	update_xp_bar()

func update_health_bar():
	if health_bar:
		health_bar.value = float(health) / max_health * 100

func update_xp_bar():
	if xp_bar:
		xp_bar.value = float(xp) / max_xp * 100

func die():
	queue_free()
