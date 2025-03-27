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

# Try to find a detour for a water tile.
func find_detour(tile: Vector2i, tilemap) -> Vector2i:
	# Check adjacent tiles for one that is walkable, not water, and unoccupied.
	for neighbor in get_adjacent_tiles(tile):
		if tilemap._is_tile_walkable(neighbor) and not tilemap.is_water_tile(neighbor) and not tilemap.is_tile_occupied(neighbor):
			return neighbor
	# If no alternative found, return the original tile.
	return tile

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
			
			# Check for adjacent enemies before pathfinding
			if unit.has_method("has_adjacent_enemy") and unit.has_adjacent_enemy():
				print("⚔️ Enemy", unit.name, "has adjacent target. Skipping movement.")
				unit.has_moved = true
				await _run_safe_enemy_action(unit)
				return

			# Find a target and compute a path that avoids water if possible.
			var target = find_closest_enemy(unit)
			var path = []
			while target:
				# Get a path from the unit's tile to the target's tile.
				path = tilemap.astar.get_point_path(unit.tile_pos, target.tile_pos)
				# Check that there is at least one valid step (beyond the starting tile)
				# that is both walkable and not water.
				var has_valid_step = false
				for i in range(1, path.size()):
					var step = path[i]
					if tilemap._is_tile_walkable(step) and not tilemap.is_water_tile(step):
						has_valid_step = true
						break
				if has_valid_step:
					break
				else:
					print("❌ Target", target.name, "is unreachable via land avoiding water")
					target = find_next_reachable_enemy(unit, [target])
			
			if target and path.size() > 1:
				print("🎯 Final target:", target.name)
				print("🧭 Path to target:", path)
				var max_steps = min(unit.movement_range, path.size() - 1)
				var next_step: Vector2i = Vector2i(-1, -1)
				for i in range(1, max_steps + 1):
					var candidate: Vector2i = path[i]
					
					# If the candidate is water, attempt a detour.
					if tilemap.is_water_tile(candidate):
						var detour_candidate = find_detour(candidate, tilemap)
						# If detour_candidate is different and valid, use it.
						if detour_candidate != candidate:
							candidate = detour_candidate
						else:
							# No detour available; skip this candidate.
							continue

					# Recalculate the path from the unit’s current position to the candidate.
					var candidate_path = await unit.compute_path(unit.tile_pos, candidate)
					if candidate_path.is_empty():
						continue  # Candidate is no longer reachable

					# Check each cell along the candidate path (skipping the starting cell).
					var path_clear = true
					for j in range(1, candidate_path.size()):
						var cell: Vector2i = Vector2i(candidate_path[j])
						if cell == unit.tile_pos:
							continue
						if tilemap.is_water_tile(cell):
							path_clear = false
							break
					if not path_clear:
						continue

					# If we reach here, the candidate (or its detour) is valid.
					next_step = candidate
					# Continue checking for further candidates so that next_step ends up as the furthest valid candidate.
				if next_step != Vector2i(-1, -1):
					print("🚶 Planning move to:", next_step)
					unit.plan_move(next_step)
				else:
					print("⛔ No valid movement tile found within range for", unit.name)
			
			# Execute the enemy's planned actions.
			await unit.execute_actions()
			
			# Add a delay after the enemy turn to ensure grid/tile_pos updates propagate.
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
