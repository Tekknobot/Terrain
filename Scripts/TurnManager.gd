extends Node

signal turn_started(current_team)
signal turn_ended(current_team)

enum Team { ENEMY, PLAYER }

var turn_order = [Team.PLAYER, Team.ENEMY]
var current_turn_index := 0
var active_units := []
var active_unit_index := 0

var initial_player_unit_count: int = 6
var total_damage_dealt: int = 0

func _ready():
	# Record the initial number of player units.
	initial_player_unit_count = get_tree().get_nodes_in_group("Units").filter(func(u): return u.is_player).size()

	# Wait one frame so TileMap can spawn units first
	await get_tree().create_timer(0.5).timeout
	call_deferred("_initialize_turns")

func _initialize_turns():
	_populate_units()
	print("TurnManager loaded units:", active_units.size(), active_units)
	start_turn()

func _populate_units():
	active_units = get_tree().get_nodes_in_group("Units")

func start_turn():
	var team = turn_order[current_turn_index]

	var player_units_exist = false
	var enemy_units_exist = false
	for u in get_tree().get_nodes_in_group("Units"):
		if u.is_player:
			player_units_exist = true
		else:
			enemy_units_exist = true

	if not player_units_exist or not enemy_units_exist:
		var result = ""
		if not player_units_exist:
			result = "lose"
		elif not enemy_units_exist:
			result = "win"
		
		# Calculate stats and rewards (using your previously defined functions)
		var stats = {
			"units_lost": calculate_units_lost(),    # TODO: Ensure this function returns a valid value
			"damage_dealt": calculate_damage_dealt()   # TODO: Ensure this function returns a valid value
		}
		var rewards = {
			"xp": calculate_xp_reward(),               # TODO: Implement your XP logic
			"coins": calculate_coins_reward()          # TODO: Implement your coins logic
		}
		
		_show_game_over_screen(result, stats, rewards)
		
		print("🏁 Game Over — no units remain for one team. Turn will not start.")
		return  # Prevent starting turn if game over

	var team_name = "UNKNOWN"
	if team == Team.PLAYER:
		team_name = "PLAYER"
	elif team == Team.ENEMY:
		team_name = "ENEMY"
	
	print("🔁 Starting turn for:", team_name)
	
	emit_signal("turn_started", team)
	_start_unit_action(team)

# Helper to return adjacent positions (4-directional)
func get_adjacent_tiles(tile: Vector2i) -> Array:
	return [
		tile + Vector2i(1, 0),
		tile + Vector2i(-1, 0),
		tile + Vector2i(0, 1),
		tile + Vector2i(0, -1)
	]

func find_detour(tile: Vector2i, tilemap, target: Vector2i, movement_range: int) -> Vector2i:
	var path = tilemap.get_weighted_path(tile, target)
	if path.is_empty():
		return tile
	# Limit the search to the first 'movement_range' steps (or the path length, whichever is smaller)
	var max_index = min(path.size() - 1, movement_range)
	# Search backward from the furthest reachable tile toward the start.
	for i in range(max_index, 0, -1):
		if not tilemap.is_water_tile(path[i]):
			return path[i]
	return tile


# Helper: Manhattan distance (lower is better)
func manhattan_distance(a: Vector2i, b: Vector2i) -> int:
	return abs(a.x - b.x) + abs(a.y - b.y)

# Evaluate a candidate tile.
# +50 bonus if the candidate is adjacent to any player unit.
# Then subtract the Manhattan distance from candidate to target.
func evaluate_candidate(candidate: Vector2i, unit, tilemap, target) -> int:
	var score = 0
	# Check adjacent tiles (4-directional) for a player unit.
	for dir in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
		var neighbor = candidate + dir
		# Assuming TileMap has a get_unit_at_tile() method.
		var other = tilemap.get_unit_at_tile(neighbor)
		if other and other.is_player:
			score += 50
			break
	# A lower distance to the target is better.
	score -= manhattan_distance(candidate, target.tile_pos)
	return score

func _start_unit_action(team):
	active_units = active_units.filter(is_instance_valid)
	
	while active_unit_index < active_units.size():
		var unit = active_units[active_unit_index]
		if not is_instance_valid(unit):
			active_unit_index += 1
			continue
		
		# Enemy branch:
		if team == Team.ENEMY and not unit.is_player:
			# First, plan movement toward the closest enemy.
			var target = find_closest_enemy(unit)
			var path = []
			if target:
				var tilemap = get_tree().get_current_scene().get_node("TileMap")
				tilemap.update_astar_grid()
				path = await unit.compute_path(unit.tile_pos, target.tile_pos)
			if path.size() > 1:
				# Move as far as allowed by the unit's movement_range.
				var max_steps = min(unit.movement_range, path.size() - 1)
				var move_tile = path[max_steps]
				print("🚶 Planning move to:", move_tile, "for enemy", unit.name)
				unit.plan_move(move_tile)
			else:
				print("❌ No valid path found. Enemy won't move this turn.")
			
			# Execute the planned movement.
			await unit.execute_actions()
					
			# Now, if the unit is ranged, check for a valid target.
			if unit.unit_type == "Ranged" or unit.unit_type == "Support":
				var ranged_target = _find_ranged_target(unit)
				if ranged_target:
					print("🤖 Ranged enemy", unit.name, "attacking target", ranged_target.name)
					unit.has_moved = true
					await unit.auto_attack_ranged(ranged_target, unit)
				# (Optional: you might let a melee enemy also attack here if adjacent.)
			else:
				# For melee units, check if there is an adjacent enemy to attack.
				if unit.has_method("has_adjacent_enemy") and unit.has_adjacent_enemy():
					print("⚔️ Enemy", unit.name, "has adjacent target. Skipping movement attack.")
					unit.has_moved = true
					await _run_safe_enemy_action(unit)
			
			unit_finished_action(unit)
			return
		
		# Player branch.
		elif team == Team.PLAYER and unit.is_player:
			print("🧍 Player unit turn:", unit.name)
			unit.start_turn()
			return
		
		active_unit_index += 1
	
	end_turn()

func _run_safe_enemy_action(unit):
	await unit.auto_attack_adjacent()

	# If the unit died while attacking (e.g. counter damage), skip its turn
	if not is_instance_valid(unit):
		print("☠️ Unit died during auto-attack. Skipping remaining actions.")
		active_unit_index += 1
		await get_tree().process_frame  # let the engine free nodes cleanly
		_start_unit_action(turn_order[current_turn_index])
		return

	await unit.execute_actions()

	if is_instance_valid(unit):
		unit_finished_action(unit)
	else:
		print("☠️ Unit died during execution. Skipping.")
		active_unit_index += 1
		await get_tree().process_frame
		_start_unit_action(turn_order[current_turn_index])

func find_next_reachable_enemy(unit, exclude := []):
	var candidates = []
	for u in get_tree().get_nodes_in_group("Units"):
		if u.is_player != unit.is_player and u not in exclude:
			candidates.append(u)

	candidates.sort_custom(func(a, b): return unit.tile_pos.distance_to(a.tile_pos) < unit.tile_pos.distance_to(b.tile_pos))

	for candidate in candidates:
		return candidate  # Return the next closest one not excluded

	return null

func end_turn(game_over: bool = false):
   # Calculate or gather stats for display.
	var stats = {
		"units_lost": calculate_units_lost(),
		"damage_dealt": calculate_damage_dealt()
	}
	var rewards = {
		"xp": calculate_xp_reward(),
		"coins": calculate_coins_reward()
	}
	
	# Check game over conditions.
	var player_units_exist = false
	var enemy_units_exist = false
	for u in get_tree().get_nodes_in_group("Units"):
		if u.is_player:
			player_units_exist = true
		else:
			enemy_units_exist = true
	
	if not player_units_exist:
		print("Game Over - You Lost!")
		_show_game_over_screen("lose", stats, rewards)
		return
	elif not enemy_units_exist:
		print("Game Over - You Won!")
		_show_game_over_screen("win", stats, rewards)
		return

	
	emit_signal("turn_ended", turn_order[current_turn_index])

	if game_over:
		print("🏁 Game Over detected in end_turn, aborting spawn.")
		return
	
	for u in get_tree().get_nodes_in_group("Units"):
		if u.is_player:
			player_units_exist = true
		else:
			enemy_units_exist = true
	
	if not player_units_exist or not enemy_units_exist:
		print("🏁 Game Over — no units remain for one team.")
		return  # ← Prevent further spawning and turns if game over

	if turn_order[current_turn_index] == Team.ENEMY:
		var tilemap = get_tree().get_current_scene().get_node("TileMap")
		tilemap.spawn_new_enemy_units()
		_populate_units()

	current_turn_index = (current_turn_index + 1) % turn_order.size()
	active_unit_index = 0

	call_deferred("start_turn")


func unit_finished_action(unit):
	active_unit_index += 1
	await get_tree().process_frame  # Wait for any pending updates
	active_units = active_units.filter(is_instance_valid)
	_start_unit_action(turn_order[current_turn_index])

func find_closest_enemy(unit) -> Node:
	var closest: Node = null
	var shortest := INF

	for u in get_tree().get_nodes_in_group("Units"):
		if not is_instance_valid(u):
			continue
		if u.is_player != unit.is_player:
			var dist = unit.tile_pos.distance_to(u.tile_pos)
			if dist < shortest:
				shortest = dist
				closest = u

	return closest if is_instance_valid(closest) else null

func find_weakest_enemy(unit) -> Node:
	var enemies := get_tree().get_nodes_in_group("Units").filter(
		func(u): return is_instance_valid(u) and u.is_player != unit.is_player
	)

	if enemies.is_empty():
		return null

	enemies.sort_custom(func(a, b):
		if a.health == b.health:
			return unit.tile_pos.distance_to(a.tile_pos) < unit.tile_pos.distance_to(b.tile_pos)
		return a.health < b.health
	)

	return enemies[0]

func _find_ranged_target(unit) -> Node:
	var candidates = []
	for other in get_tree().get_nodes_in_group("Units"):
		# Check for an enemy unit.
		if other.is_player != unit.is_player:
			# Compute Manhattan distance.
			var dx = abs(unit.tile_pos.x - other.tile_pos.x)
			var dy = abs(unit.tile_pos.y - other.tile_pos.y)
			var manh_dist = dx + dy
			if manh_dist <= unit.attack_range:
				candidates.append(other)
	if candidates.size() > 0:
		# Sort candidates by Manhattan distance (closest first).
		candidates.sort_custom(func(a, b):
			var a_dist = abs(unit.tile_pos.x - a.tile_pos.x) + abs(unit.tile_pos.y - a.tile_pos.y)
			var b_dist = abs(unit.tile_pos.x - b.tile_pos.x) + abs(unit.tile_pos.y - b.tile_pos.y)
			return a_dist < b_dist
		)
		return candidates[0]
	return null

func _show_game_over_screen(result: String, stats: Dictionary, rewards: Dictionary) -> void:
	# Now wait if needed
	await get_tree().create_timer(1).timeout 
	
	var game_over_scene = preload("res://Scenes/GameOver.tscn").instantiate()
	# Add it immediately so that _ready() is called
	get_tree().get_current_scene().add_child(game_over_scene) 
	# Then set the result (which can also trigger updates in the UI)
	game_over_scene.set_result(result, stats, rewards)

func calculate_units_lost() -> int:
	return TurnManager.player_units_lost

func record_damage(amount: int) -> void:
	total_damage_dealt += amount

func calculate_damage_dealt() -> int:
	return total_damage_dealt

# Global variables that should be updated during gameplay.
var enemy_units_destroyed: int = 0  # Increment when an enemy dies.
var player_units_lost: int = 0  # Increment when a player unit dies.

func calculate_xp_reward() -> int:
	# Calculate XP based on a combination of:
	#  - XP from damage: 1 XP per 100 points of damage dealt.
	#  - XP from enemy kills: 5 XP per enemy unit destroyed.
	#  - Penalty for player losses: subtract 2 XP per player unit lost.
	var xp_from_damage = total_damage_dealt / 100
	var xp_from_enemies = enemy_units_destroyed * 5
	var xp_loss_penalty = player_units_lost * 2

	var xp_reward = xp_from_damage + xp_from_enemies - xp_loss_penalty

	# Ensure XP reward is not negative.
	if xp_reward < 0:
		xp_reward = 0

	# TODO: Adjust the formula or multipliers to better fit your desired progression.
	return xp_reward

func calculate_coins_reward() -> int:
	# Example factors for coins reward:
	# - Award 10 coins per enemy unit destroyed.
	# - Award additional coins based on total damage dealt, here 1 coin per 200 damage points.
	var coins_from_kills = enemy_units_destroyed * 10
	var coins_from_damage = total_damage_dealt / 200  # You can adjust the divisor as needed.

	var coins_reward = coins_from_kills + coins_from_damage

	# TODO: Optionally, add bonuses or penalties based on mission objectives or player performance.

	# Ensure the coins reward is at least zero.
	if coins_reward < 0:
		coins_reward = 0

	return coins_reward

func reset_match_stats() -> void:
	player_units_lost = 0
	total_damage_dealt = 0
	enemy_units_destroyed = 0
	# Optionally, reset initial_player_unit_count here if needed.
	initial_player_unit_count = get_tree().get_nodes_in_group("Units").filter(
		func(u): return u.is_player
	).size()
	print("Match stats reset!")
