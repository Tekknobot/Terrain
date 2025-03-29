extends Node

signal turn_started(current_team)
signal turn_ended(current_team)

enum Team { ENEMY, PLAYER }

var turn_order = [Team.PLAYER, Team.ENEMY]
var current_turn_index := 0
var active_units := []
var active_unit_index := 0

func _ready():
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

		if team == Team.ENEMY and not unit.is_player:
			print("🤖 Enemy taking turn:", unit.name)
			var tilemap = get_tree().get_current_scene().get_node("TileMap")

			# If there's an adjacent enemy, skip movement and just attack.
			if unit.has_method("has_adjacent_enemy") and unit.has_adjacent_enemy():
				print("⚔️ Enemy", unit.name, "has adjacent target. Skipping movement.")
				unit.has_moved = true
				await _run_safe_enemy_action(unit)
				return
			
			# Find a target (closest).
			var target = find_closest_enemy(unit)
			
			# Compute the path to the target if it exists.
			var path = []
			if target:
				tilemap.update_astar_grid()
				path = await unit.compute_path(unit.tile_pos, target.tile_pos)
			
			# If we found a path with at least 2 tiles, move partially.
			if path.size() > 1:
				# partial movement: pick tile at index min(movement_range, path.size() - 1)
				var max_steps = min(unit.movement_range, path.size() - 1)
				var move_tile = path[max_steps]
				print("🚶 Planning move to:", move_tile, "within", unit.movement_range, "steps.")
				unit.plan_move(move_tile)
			else:
				print("❌ No valid path found. Enemy won't move this turn.")
			
			# Execute the enemy's planned actions (movement + potential attack).
			await unit.execute_actions()
			await get_tree().create_timer(0).timeout

			# Mark this unit done and move on.
			unit_finished_action(unit)
			return
		
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

func end_turn():
	emit_signal("turn_ended", turn_order[current_turn_index])
	current_turn_index = (current_turn_index + 1) % turn_order.size()
	active_unit_index = 0

	if active_units.is_empty():
		print("Game Over — no units remain")
		return

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
