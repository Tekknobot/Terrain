extends Area2D

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

var has_moved
var has_attacked

const Y_OFFSET := -8.0
var true_position := Vector2.ZERO  # we manage this ourselves

var visited_tiles: Array = []
@export var water_tile_id := 6

func _ready():
	var tilemap = get_tree().get_current_scene().get_node("TileMap")
	tile_pos = tilemap.local_to_map(tilemap.to_local(global_position))  # 🔥 Set this!
	add_to_group("Units")  # 🔥 Also make sure they’re in the group
	update_z_index()
	update_health_bar()
	update_xp_bar()

func _process(delta):
	update_z_index()
	_update_tile_pos()  # Ensure tile_pos is current

func _update_tile_pos():
	var tilemap = get_tree().get_current_scene().get_node("TileMap")
	tile_pos = tilemap.local_to_map(tilemap.to_local(global_position))

func update_z_index():
	z_index = int(position.y)

### PLAYER TURN ###
func start_turn():
	# Wait for player input; call on_player_done() when action is complete
	return

func on_player_done():
	TurnManager.unit_finished_action(self)

func compute_path(from: Vector2i, to: Vector2i) -> Array:
	await get_tree().process_frame
	var tilemap = get_tree().get_current_scene().get_node("TileMap")
	tilemap.update_astar_grid()  # 🔥 Crucial step!
	return tilemap.astar.get_point_path(from, to)

func _move_one(dest: Vector2i) -> void:
	var tilemap = get_tree().get_current_scene().get_node("TileMap")
	var world_target = tilemap.to_global(tilemap.map_to_local(dest)) + Vector2(0, Y_OFFSET)

	var sprite = $AnimatedSprite2D
	if sprite:
		sprite.play("move")
		sprite.flip_h = global_position.x < world_target.x

	var speed := 100.0  # pixels/sec
	
	while global_position.distance_to(world_target) > 1.0:
		var delta = get_process_delta_time()
		global_position = global_position.move_toward(world_target, speed * delta)
		await get_tree().process_frame

	global_position = world_target  # explicitly set position to remove small offsets
	
	tile_pos = dest
	if sprite:
		sprite.play("default")	

func move_to(dest: Vector2i) -> void:
	# Update the grid and wait for a frame so all positions are up-to-date
	var tilemap = get_tree().get_current_scene().get_node("TileMap")	
	var path = tilemap.get_weighted_path(tile_pos, dest)
	if path.is_empty():
		emit_signal("movement_finished")
		return

	for step in path:
		await _move_one(step)
	
	tilemap.update_astar_grid()
	await get_tree().process_frame

	emit_signal("movement_finished")
	has_moved = true

func auto_attack_adjacent():
	var directions = [
		Vector2i(0, -1), Vector2i(0, 1),
		Vector2i(-1, 0), Vector2i(1, 0)
	]

	var tilemap = get_tree().get_current_scene().get_node("TileMap")
	var raw_units = get_tree().get_nodes_in_group("Units")
	var units = []

	# Snapshot all valid units up front.
	for u in raw_units:
		if is_instance_valid(u):
			units.append(u)

	for dir in directions:
		var actual_pos = tilemap.local_to_map(tilemap.to_local(global_position))
		var check_pos = actual_pos + dir

		for unit in units:
			# Skip invalid units and self.
			if not is_instance_valid(unit) or unit == self:
				continue
			# If the unit is adjacent and on the opposing team.
			if unit.tile_pos == check_pos and unit.is_player != is_player:
				var push_pos = unit.tile_pos + dir

				# 🔥 Damage the target and flash white.
				var died = unit.take_damage(damage)
				unit.flash_white()

				# 🧱 Animate the attacker.
				var sprite = get_node("AnimatedSprite2D")
				if sprite:
					# 🎵 Play attack sound before animation.
					tilemap.play_attack_sound(global_position)
					# Face the appropriate direction.
					if dir.x != 0:
						sprite.flip_h = dir.x > 0
					elif dir.y != 0:
						sprite.flip_h = true
					sprite.play("attack")
					await sprite.animation_finished
					sprite.play("default")

				# 🎖 Grant XP if the target died from the damage.
				if died:
					gain_xp(50)
					continue  # Unit is already dead.

				# ➡ Push Logic:
				# Do not push into water.
				var tile_id = tilemap.get_cell_source_id(0, push_pos)
				if tile_id == water_tile_id:
					# Skip push logic if destination is water.
					continue

				# NEW: If the push position is off the tilemap, animate the unit being pushed off.
				if not tilemap.is_within_bounds(push_pos):
					var target_pos = tilemap.to_global(tilemap.map_to_local(push_pos)) + Vector2(0, Y_OFFSET)
					var push_speed = 150.0  # Adjust push speed as desired.
					# Animate the unit moving toward the off-map target.
					while unit.global_position.distance_to(target_pos) > 1.0:
						var delta = get_process_delta_time()
						unit.global_position = unit.global_position.move_toward(target_pos, push_speed * delta)
						await get_tree().process_frame
					# Optionally wait a short time to let the animation complete.
					await get_tree().create_timer(0.2).timeout
					unit.die()
					continue


				# If push position is within bounds, perform push animation.
				if tilemap.is_within_bounds(push_pos):
					var target_pos = tilemap.to_global(tilemap.map_to_local(push_pos)) + Vector2(0, Y_OFFSET)
					var push_speed = 150.0  # Adjust push speed as desired.
					while unit.global_position.distance_to(target_pos) > 1.0:
						var delta = get_process_delta_time()
						unit.global_position = unit.global_position.move_toward(target_pos, push_speed * delta)
						await get_tree().process_frame
					unit.global_position = target_pos
					unit.tile_pos = push_pos  # Update the pushed unit's tile position.

					# After the push animation, check for occupancy by another entity.
					# We ignore the pushed unit itself.
					if tilemap.is_tile_occupied(push_pos):
						var occupants = get_occupants_at(push_pos, unit)
						if occupants.size() > 0:
							for occ in occupants:
								# If the occupant is a structure.
								if occ.is_in_group("Structures"):
									var occ_sprite = occ.get_node("AnimatedSprite2D")
									if occ_sprite:
										occ_sprite.play("demolished")
										occ_sprite.get_parent().modulate = Color(1, 1, 1, 1)
								# If the occupant is another unit.
								elif occ.is_in_group("Units"):
									await get_tree().create_timer(0.2).timeout
									occ.take_damage(damage)  # Adjust damage as needed.
									occ.shake()
							# In either case, the pushed unit dies.
							unit.die()
					# Update the AStar grid after any changes.
					tilemap.update_astar_grid()

# Helper function to retrieve the occupant (unit or structure) at a given tile.
func get_occupants_at(pos: Vector2i, ignore: Node = null) -> Array:
	var occupants = []
	# Check units.
	for unit in get_tree().get_nodes_in_group("Units"):
		if is_instance_valid(unit) and unit.tile_pos == pos and unit != ignore:
			occupants.append(unit)
	# Check structures.
	for structure in get_tree().get_nodes_in_group("Structures"):
		if is_instance_valid(structure) and structure.tile_pos == pos and structure != ignore:
			occupants.append(structure)
	return occupants

# Example helper to spawn an explosion at a given position.
func spawn_explosion_at(pos: Vector2):
	# Replace the following with your actual explosion scene path and logic.
	var explosion_scene = preload("res://Scenes/VFX/Explosion.tscn")
	var explosion = explosion_scene.instantiate()
	explosion.position = pos
	get_tree().get_current_scene().add_child(explosion)

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
func take_damage(amount: int) -> bool:
	health = max(health - amount, 0)
	update_health_bar()
	if health == 0:
		die()
		return true  # 💀 Unit is dead
	return false

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
	var explosion = preload("res://Scenes/VFX/Explosion.tscn").instantiate()
	explosion.position = global_position + Vector2(0, -8)
	tilemap.add_child(explosion)

	# Check if this was the last unit on the team
	await get_tree().process_frame  # Wait 1 frame before freeing
	queue_free()

	await get_tree().process_frame  # Let scene update

	# 🧠 Check if game is over
	var units = get_tree().get_nodes_in_group("Units")
	var has_players = false
	var has_enemies = false
	for u in units:
		if not is_instance_valid(u):
			continue
		if u.is_player:
			has_players = true
		else:
			has_enemies = true

	if not has_players or not has_enemies:
		print("🏁 Game Over — One team has no remaining units.")
		var tm = get_node_or_null("/root/TurnManager")
		if tm:
			tm.end_turn(true)  # We'll add this next

var _flash_tween: Tween = null
var _flash_shader := preload("res://Textures/flash.gdshader")
var _original_material: Material = null

func flash_white():
	var sprite = $AnimatedSprite2D
	if not sprite:
		return

	# Kill any existing flash
	if _flash_tween:
		_flash_tween.kill()
		sprite.self_modulate = Color(1,1,1,1)
		_flash_tween = null

	_flash_tween = create_tween()
	for i in range(3):
		_flash_tween.tween_property(sprite, "self_modulate", Color(1,1,1,1), 0.1)
		_flash_tween.tween_property(sprite, "self_modulate", Color(1,1,1,0), 0.1)
	_flash_tween.tween_callback(func():
		sprite.self_modulate = Color(1,1,1,1)
		_flash_tween = null
	)


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

var queued_move: Vector2i = Vector2i(-1, -1)
var queued_attack_target: Node2D = null

func plan_move(dest: Vector2i):
	var tilemap = get_tree().get_current_scene().get_node("TileMap")
	
	# Use BFS to find all reachable tiles within movement_range.
	var frontier = [tile_pos]
	var distances = { tile_pos: 0 }
	var parents = {}  # Record each tile's parent for path reconstruction.
	var candidates = []  # All reachable tiles (except the starting tile)
	
	while frontier.size() > 0:
		var current = frontier.pop_front()
		var d = distances[current]
		
		# Add reached tile to candidates (ignore the starting tile).
		if current != tile_pos:
			candidates.append(current)
		
		# Stop expanding if we've reached the movement limit.
		if d == movement_range:
			continue
		
		# Check the four cardinal neighbors.
		for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var neighbor = current + dir
			if tilemap.is_within_bounds(neighbor) and not distances.has(neighbor) and tilemap._is_tile_walkable(neighbor) and not tilemap.is_tile_occupied(neighbor):
				distances[neighbor] = d + 1
				parents[neighbor] = current  # Record where we came from.
				frontier.append(neighbor)
	
	# First, if the destination is directly reachable, reconstruct the full path.
	if distances.has(dest):
		var path = []
		var current = dest
		# Backtrack from destination to the starting tile.
		while current != tile_pos:
			path.insert(0, current)
			current = parents[current]
		# Determine how many steps to take:
		# If the full path is longer than our movement_range, take the tile at index (movement_range - 1).
		# Otherwise, take the final destination tile.
		var steps_to_take = min(path.size(), movement_range)
		var move_target = path[steps_to_take - 1]
		queued_move = move_target
		visited_tiles.append(move_target)
		print("🚶 Direct path: planning move along path to:", move_target)
		return
	else:
		print("⛔ Desired destination", dest, "is not reachable (blocked or out of range)")
	
	# NEW: Check for any candidate that puts the enemy within attack range.
	# This check is independent of any penalties.
	var attack_candidates: Array = []
	for candidate in candidates:
		# If candidate tile is within attack range of the enemy (target at dest).
		if candidate.distance_to(dest) <= attack_range:
			attack_candidates.append(candidate)
			
	if attack_candidates.size() > 0:
		# Choose the candidate closest to the target.
		var best_candidate: Vector2i = attack_candidates[0]
		var best_cost = best_candidate.distance_to(dest)
		for candidate in attack_candidates:
			var cost = candidate.distance_to(dest)
			if cost < best_cost:
				best_cost = cost
				best_candidate = candidate
		queued_move = best_candidate
		visited_tiles.append(best_candidate)
		print("🚶 Attack move found, planning move to:", best_candidate)
		return
	
	# Fallback: choose from candidate tiles using a cost function.
	var best_candidate: Vector2i = tile_pos
	var best_cost = INF
	for candidate in candidates:
		var euclid = candidate.distance_to(dest)
		var extra_cost = 0
		
		# Apply penalties if reusing the same move or if the tile has already been visited.
		if candidate == queued_move:
			extra_cost += 2
		if visited_tiles.has(candidate):
			extra_cost += 5

		# Reward candidate if it puts the enemy within its attack range.
		if candidate.distance_to(dest) <= attack_range:
			extra_cost -= 10  # Adjust bonus value as needed.
		
		var cost = euclid + extra_cost
		if cost < best_cost:
			best_cost = cost
			best_candidate = candidate
	
	if best_candidate != tile_pos:
		queued_move = best_candidate
		visited_tiles.append(best_candidate)
		print("🚶 Fallback move found, planning move to:", best_candidate)
	else:
		print("⛔ No valid tile found within movement range. This unit will not move this turn.")

func plan_attack(target: Node2D):
	queued_attack_target = target

func clear_actions():
	queued_move = Vector2i(-1, -1)
	queued_attack_target = null

func execute_actions():
	if queued_move != Vector2i(-1, -1):
		await move_to(queued_move)
		has_moved = true
		queued_move = Vector2i(-1, -1)

		if not is_instance_valid(self):
			print("☠️ Unit died after move")
			return

		# 🧠 Enemy auto-attacks after moving
		if not is_player:
			await auto_attack_adjacent()
			if not is_instance_valid(self):
				print("☠️ Unit died after auto-attack")
				return

	if queued_attack_target:
		# 💥 Double-check target validity
		if not is_instance_valid(queued_attack_target):
			print("❌ Target no longer exists")
			queued_attack_target = null
			return

		if queued_attack_target == self:
			print("🚨 Cannot attack self")
			queued_attack_target = null
			return

		# Face and animate attack
		var dir = queued_attack_target.tile_pos - tile_pos
		var sprite = get_node("AnimatedSprite2D")

		# ← PLACE THIS HERE
		if sprite and dir.x != 0:
			sprite.flip_h = dir.x > 0

		var tilemap = get_tree().get_current_scene().get_node("TileMap")
		tilemap.play_attack_sound(global_position)

		if sprite:
			sprite.play("attack")
			await sprite.animation_finished
			if not is_instance_valid(self):
				print("☠️ Attacker died mid-attack")
				return
			sprite.play("default")

		has_attacked = true
		queued_attack_target = null

	if not is_instance_valid(self):
		print("☠️ Unit died before finishing turn")
		return

	# ✅ Signal end of turn for players
	if is_player:
		var tilemap = get_tree().get_current_scene().get_node("TileMap")
		if tilemap.has_method("on_player_unit_done"):
			tilemap.on_player_unit_done(self)


func execute_all_player_actions():
	var units := get_tree().get_nodes_in_group("Units").filter(func(u): return u.is_player)
	
	for unit in units:
		if unit.has_method("execute_actions"):
			await unit.execute_actions()

	# ✅ All player actions are complete
	var turn_manager = get_node("/root/TurnManager")  # or however you access it
	if turn_manager and turn_manager.has_method("end_turn"):
		turn_manager.end_turn()

func shake():
	var original_position = global_position
	var tween = create_tween()
	# Shake right by 5 pixels.
	tween.tween_property(self, "global_position", original_position + Vector2(5, 0), 0.05)
	# Shake left by 10 pixels.
	tween.tween_property(self, "global_position", original_position - Vector2(5, 0), 0.05)
	# Return to original position.
	tween.tween_property(self, "global_position", original_position, 0.05)
