extends Node2D

@export var is_player: bool = true  
@export var unit_type: String = "Soldier"  
var health := 100
var max_health := 100
var xp := 0
var max_xp := 100

var damage = 25

@export var movement_range := 2  
@export var attack_range := 3 

var tile_pos: Vector2i

signal movement_finished

@onready var health_bar = $HealthUI
@onready var xp_bar = $XPUI


func _ready():
	var tilemap = get_tree().get_current_scene().get_node("TileMap")
	tile_pos = tilemap.local_to_map(tilemap.to_local(global_position))  # 🔥 Set this!
	add_to_group("Units")  # 🔥 Also make sure they’re in the group
	update_z_index()
	update_health_bar()
	update_xp_bar()

func _process(delta):
	update_z_index()

func update_z_index():
	z_index = int(position.y)

### PLAYER TURN ###
func start_turn():
	# Wait for player input; call on_player_done() when action is complete
	return

func on_player_done():
	TurnManager.unit_finished_action(self)

func move_to(dest: Vector2i):
	var tilemap = get_tree().get_current_scene().get_node("TileMap")
	tile_pos = dest
	global_position = tilemap.to_global(tilemap.map_to_local(dest))
	emit_signal("movement_finished")

func auto_attack_adjacent():
	var directions = [
		Vector2i(0, -1), Vector2i(0, 1),
		Vector2i(-1, 0), Vector2i(1, 0)
	]

	var tilemap = get_tree().get_current_scene().get_node("TileMap")
	var units = get_tree().get_nodes_in_group("Units")

	for dir in directions:
		# Convert actual position → reliable tile_pos
		var actual_pos = tilemap.local_to_map(tilemap.to_local(global_position))
		var check_pos = actual_pos + dir

		for unit in units:
			if unit == self:
				continue
			if unit.tile_pos == check_pos and unit.is_player != is_player:
				# Damage + visual
				unit.take_damage(damage)
				unit.flash_white()
				
				var sprite = self.get_node("AnimatedSprite2D")
				if sprite:
					sprite.play("attack")
				
				# Calculate push position
				var push_pos = unit.tile_pos + dir

				# Optional debug
				print("Trying to push", unit.unit_type, "from", unit.tile_pos, "to", push_pos)

				# Validate push destination
				if tilemap.is_within_bounds(push_pos) \
						and not tilemap.is_tile_occupied(push_pos) \
						and tilemap._is_tile_walkable(push_pos):

					unit.tile_pos = push_pos
					unit.global_position = tilemap.to_global(tilemap.map_to_local(push_pos))

				if unit.health == 0:
					gain_xp(50)
			
				tilemap.update_astar_grid()

func has_adjacent_enemy() -> bool:
	var directions = [
		Vector2i(0, -1), Vector2i(0, 1),
		Vector2i(-1, 0), Vector2i(1, 0)
	]

	var tilemap = get_tree().get_current_scene().get_node("TileMap")
	var actual_tile = tilemap.local_to_map(tilemap.to_local(global_position))
	print("\n[has_adjacent_enemy] Self tile_pos (projected):", actual_tile)

	for dir in directions:
		var check_pos = actual_tile + dir
		print("  Checking adjacent tile:", check_pos)

		for unit in get_tree().get_nodes_in_group("Units"):
			if unit == self:
				continue
			var unit_pos = tilemap.local_to_map(tilemap.to_local(unit.global_position))
			print("    Unit:", unit.name, "at", unit_pos)

			if unit_pos == check_pos and unit.is_player != is_player:
				print("    -> ENEMY FOUND:", unit.name)
				return true

	print("  No enemies found.")
	return false

func display_attack_range(range: int):
	var tilemap = get_tree().get_current_scene().get_node("TileMap")
	tilemap._highlight_range(tile_pos, range, 3)

### HEALTH & XP ###
func take_damage(amount):
	health = max(health - amount, 0)
	update_health_bar()
	if health == 0:
		die()

func gain_xp(amount):
	xp = min(xp + amount, max_xp)
	update_xp_bar()

func update_health_bar():
	if health_bar:
		health_bar.value = float(health) / max_health * 100

func update_xp_bar():
	if xp_bar:
		xp_bar.value = float(xp) / max_xp * 100

func die():
	var tilemap = get_tree().get_current_scene().get_node("TileMap")
	#tilemap.all_units.erase(self)
	var explosion = preload("res://Scenes/VFX/Explosion.tscn").instantiate()
	explosion.position = global_position + Vector2(0, -8)
	tilemap.add_child(explosion)
	queue_free()

func flash_white():
	var sprite = $AnimatedSprite2D
	if not sprite:
		return
	var original = sprite.modulate
	var t = create_tween()
	for i in range(6):
		t.tween_property(sprite, "modulate", Color(1,1,1,0), 0.1)
		t.tween_property(sprite, "modulate", original, 0.1)

func set_team(player_team: bool):
	is_player = player_team
	var sprite = $AnimatedSprite2D
	if sprite:
		sprite.modulate = Color(1,1,1) if is_player else Color(1,0.43,1)

func check_adjacent_and_attack():
	if has_adjacent_enemy():
		print("✅ Adjacent enemy detected after movement")
		display_attack_range(1)
		auto_attack_adjacent()
	else:
		print("❌ No adjacent enemy after movement")
