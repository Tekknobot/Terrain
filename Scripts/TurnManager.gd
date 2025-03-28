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

func find_detour(tile: Vector2i, tilemap) -> Vector2i:
	# Use a BFS to search for a tile that is walkable, not water, and unoccupied.
	var frontier = [tile]
	var visited = { tile: true }
	
	while frontier.size() > 0:
		var current = frontier.pop_front()
		for neighbor in get_adjacent_tiles(current):
			# Optionally, check boundaries if needed:
			# if not tilemap.is_within_bounds(neighbor):
			#     continue
			if visited.has(neighbor):
				continue
			visited[neighbor] = true
			if tilemap._is_tile_walkable(neighbor) and not tilemap.is_water_tile(neighbor) and not tilemap.is_tile_occupied(neighbor):
				return neighbor
			frontier.append(neighbor)
	
	# If no suitable detour is found, return the original tile.
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
			
			if unit.has_method("has_adjacent_enemy") and unit.has_adjacent_enemy():
				print("⚔️ Enemy", unit.name, "has adjacent target. Skipping movement.")
				unit.has_moved = true
				await _run_safe_enemy_action(unit)
				return

			var target = find_weakest_enemy(unit)
			if not target:
				target = find_closest_enemy(unit)

			var path = []
			while target:
				tilemap.update_astar_grid()
				path = await unit.compute_path(unit.tile_pos, target.tile_pos)

				var has_valid_step = false
				for i in range(1, path.size()):
					var step = path[i]
					if tilemap._is_tile_walkable(step) and not tilemap.is_water_tile(step) and not tilemap.is_tile_occupied(step):
						has_valid_step = true
						break

				if has_valid_step:
					break
				else:
					print("❌ Target", target.name, "unreachable. Finding next.")
					target = find_next_reachable_enemy(unit, [target])

			if target and path.size() > 1:
				var max_steps = min(unit.movement_range, path.size() - 1)
				
				var best_score = -INF
				var best_candidate: Vector2i = Vector2i(-1, -1)
				
				for i in range(1, max_steps + 1):
					var candidate: Vector2i = path[i]

					if tilemap.is_water_tile(candidate):
						candidate = find_detour(candidate, tilemap)
						if tilemap.is_water_tile(candidate):
							continue

					if tilemap.is_tile_occupied(candidate):
						continue  # ❗️ Explicit check here!

					tilemap.update_astar_grid()
					var candidate_path = await unit.compute_path(unit.tile_pos, candidate)
					if candidate_path.is_empty():
						continue

					var path_clear = true
					for cell in candidate_path:
						var cell_i = Vector2i(cell)
						if cell_i == unit.tile_pos:
							continue
						if tilemap.is_water_tile(cell_i) or tilemap.is_tile_occupied(cell_i):
							path_clear = false
							break

					if not path_clear:
						continue

					var score = evaluate_candidate(candidate, unit, tilemap, target)
					if score > best_score:
						best_score = score
						best_candidate = candidate

				if best_candidate != Vector2i(-1, -1):
					print("🚶 Planning move to:", best_candidate, "score:", best_score)
					unit.plan_move(best_candidate)
				else:
					print("⛔ No valid tile within range for", unit.name)
			
			await unit.execute_actions()
			await get_tree().create_timer(0).timeout
			
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
