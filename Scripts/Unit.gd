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

signal movement_finished

@onready var EXPLOSION_SCENE = preload("res://Scenes/VFX/Explosion.tscn")  # Adjust the path

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
		await ai_move()  # ← Add await here


func ai_move() -> void:
	var tilemap = get_tree().get_current_scene().get_node("TileMap")
	if tilemap == null:
		return

	var start = tile_pos
	var candidates := []
	for x in range(start.x - movement_range, start.x + movement_range + 1):
		for y in range(start.y - movement_range, start.y + movement_range + 1):
			var target = Vector2i(x, y)
			if tilemap.manhattan_distance(start, target) <= movement_range \
			   and tilemap.is_valid_spawn_ignore(self, target):
				candidates.append(target)

	if candidates.size() > 0:
		var choice = candidates[randi() % candidates.size()]
		await tilemap.move_unit(self, choice)  # ← await the movement!
	else:
		print(unit_type, "has no valid move.")
		
func choose_target_tile() -> Vector2i:
	var tilemap = get_tree().get_current_scene().get_node("TileMap")
	if tilemap == null:
		return Vector2i(-1, -1)

	var start = tile_pos

	# Step 1: Find the nearest player unit
	var nearest_player_pos: Vector2i = Vector2i(-1, -1)
	var min_distance = INF

	for unit in tilemap.all_units:
		if unit.is_player:
			var dist = tilemap.manhattan_distance(start, unit.tile_pos)
			if dist < min_distance:
				min_distance = dist
				nearest_player_pos = unit.tile_pos

	if nearest_player_pos == Vector2i(-1, -1):
		return Vector2i(-1, -1)  # No player found

	# Step 2: Gather valid candidate tiles
	var candidates: Array[Vector2i] = []

	for x in range(start.x - movement_range, start.x + movement_range + 1):
		for y in range(start.y - movement_range, start.y + movement_range + 1):
			var target = Vector2i(x, y)
			if tilemap.manhattan_distance(start, target) <= movement_range \
			and tilemap.is_valid_spawn_ignore(self, target):
				candidates.append(target)

	# Step 3: Sort by distance to the nearest player
	candidates.sort_custom(func(a, b):
		return tilemap.manhattan_distance(a, nearest_player_pos) < tilemap.manhattan_distance(b, nearest_player_pos)
	)

	# Step 4: Try each candidate to find a valid path
	for target in candidates:
		tilemap.update_astar_grid_ignore(self)
		var path = tilemap.astar.get_point_path(start, target)
		if path.size() > 1:
			return target  # Found a reachable tile

	return Vector2i(-1, -1)  # Nothing reachable


func move_along_path(path: Array):
	if path.is_empty():
		return

	var tween = create_tween()
	var tilemap = get_tree().get_current_scene().get_node("TileMap")
	if tilemap == null:
		return

	var t_size = tilemap.get_tileset().tile_size
	$AnimatedSprite2D.play("move")
	
	var previous_tile = tile_pos  # ← assigned here, before any movement

	for tile in path:
		# 🔥 Face the correct direction based on X‑movement
		_set_facing(previous_tile, tile)
		previous_tile = tile
		var world = tilemap.map_to_local(tile)
		tween.tween_property(self, "global_position", world, 0.2)
		tween.tween_callback(Callable(self, "_update_tile_pos").bind(tile))

	await tween.finished
	emit_signal("movement_finished")
	
	$AnimatedSprite2D.play("default")
	tilemap.update_astar_grid()
	tilemap.clear_movement_highlight()

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
	var tilemap = get_tree().get_current_scene().get_node("TileMap")
	if tilemap and tilemap.all_units.has(self):
		var index = tilemap.all_units.find(self)

		# ⚠️ Adjust active_unit_index if needed
		if not is_player and index <= tilemap.active_unit_index:
			tilemap.active_unit_index -= 1

		tilemap.all_units.erase(self)

		# 💥 Play explosion effect (optional)
		var EXPLOSION_SCENE = preload("res://Scenes/VFX/Explosion.tscn")  # Adjust path
		var explosion = EXPLOSION_SCENE.instantiate()
		explosion.position = global_position + Vector2(0, -8)  # Optional offset
		tilemap.add_child(explosion)

	queue_free()

func _set_facing(from: Vector2i, to: Vector2i) -> void:
	var delta = to - from

	# Horizontal flip (left/right)
	if delta.x > 0:
		$AnimatedSprite2D.flip_h = true
	elif delta.x < 0:
		$AnimatedSprite2D.flip_h = false

	# Vertical flip (up/down)
	if delta.y > 0:
		$AnimatedSprite2D.flip_h = false   # moving down → normal
	elif delta.y < 0:
		$AnimatedSprite2D.flip_h = true    # moving up → flipped vertically

func flash_white():
	var sprite = $AnimatedSprite2D
	if sprite == null:
		return

	var flash_tween = create_tween()

	for i in range(6):  # Repeat the flash pattern 3 times
		# Flash full white
		flash_tween.tween_property(sprite, "modulate", Color(1, 1, 1), 0.05)
		# Transparent white
		flash_tween.tween_property(sprite, "modulate", Color(1, 1, 1, 0.0), 0.05)
		# Black
		flash_tween.tween_property(sprite, "modulate", Color(0, 0, 0), 0.05)
		# Back to normal
		flash_tween.tween_property(sprite, "modulate", Color(1, 1, 1), 0.05)

# Returns all map‑coordinates this unit could legally move to this turn
func get_reachable_tiles() -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	var tilemap = get_tree().get_current_scene().get_node("TileMap")
	if tilemap == null:
		return tiles

	var frontier = [tile_pos]
	var visited = {tile_pos: 0}

	while frontier.size() > 0:
		var cur = frontier.pop_front()
		var dist = visited[cur]
		if dist >= movement_range:
			continue

		for dir in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
			var nxt = cur + dir
			if not visited.has(nxt) and tilemap.is_valid_spawn_ignore(self, nxt):
				visited[nxt] = dist + 1
				frontier.append(nxt)
				tiles.append(nxt)
	return tiles
