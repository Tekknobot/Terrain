extends Node2D

@export var is_player: bool = true  
@export var unit_type: String = "Soldier"  
var health := 100
var max_health := 100
var xp := 0
var max_xp := 100
var movement_range := 3  

@onready var health_bar = $HealthUI
@onready var xp_bar = $XPUI

var tile_pos: Vector2i

func _ready():
	update_tile_pos_from_world()
	update_z_index()
	update_health_bar()
	update_xp_bar()

func set_team(player_team: bool):
	is_player = player_team
	if is_player:
		modulate = Color(1, 1, 1)
	else:
		modulate = Color(1, 110/255.0, 1)

func update_z_index():
	z_index = int(position.y)

func _process(delta):
	update_z_index()

### TURN & MOVEMENT ###
func start_turn():
	var tilemap = get_tree().get_current_scene().get_node("TileMap")
	if tilemap != null:
		tilemap.highlight_movement_range(self)
	if is_player:
		print(unit_type + " — select a tile")
	else:
		ai_move()

func ai_move():
	var tilemap = get_tree().get_current_scene().get_node("TileMap")
	if tilemap == null:
		return
	var offset = Vector2i(randi_range(-movement_range, movement_range), randi_range(-movement_range, movement_range))
	var target = tile_pos + offset
	if tilemap.is_valid_spawn(target):
		tilemap.move_unit(self, target)

func move_along_path(path: Array):
	if path.is_empty():
		return

	var tween = create_tween()
	var tilemap = get_tree().get_current_scene().get_node("TileMap")
	if tilemap == null:
		return

	var t_size = tilemap.get_tileset().tile_size
	$AnimatedSprite2D.play("move")

	for tile in path:
		var world = tilemap.map_to_local(tile)
		tween.tween_property(self, "global_position", world, 0.2)
		tween.tween_callback(Callable(self, "_update_tile_pos").bind(tile))

	await tween.finished
	$AnimatedSprite2D.play("default")
	tilemap.update_astar_grid()

func _update_tile_pos(new_tile: Vector2i) -> void:
	tile_pos = new_tile

### TILE_POS SYNC ###
func update_tile_pos_from_world():
	var tilemap = get_tree().get_current_scene().get_node("TileMap")
	if tilemap != null:
		tile_pos = tilemap.local_to_map(global_position)

### HEALTH & XP ###
func take_damage(amount: int):
	health = max(health - amount, 0)
	update_health_bar()
	if health == 0:
		die()

func gain_xp(amount: int):
	xp = min(xp + amount, max_xp)
	update_xp_bar()

func update_health_bar():
	if health_bar != null:
		health_bar.value = float(health) / max_health * 100

func update_xp_bar():
	if xp_bar != null:
		xp_bar.value = float(xp) / max_xp * 100

func die():
	queue_free()

func _set_facing(from: Vector2i, to: Vector2i) -> void:
	var delta = to - from
	if delta.x > 0:
		$AnimatedSprite2D.flip_h = true
	elif delta.x < 0:
		$AnimatedSprite2D.flip_h = false
