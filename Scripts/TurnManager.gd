extends Node

signal turn_started(current_team)
signal turn_ended(current_team)

enum Team { ENEMY, PLAYER }

var turn_order = [Team.ENEMY, Team.PLAYER]
var current_turn_index := 0
var active_units := []
var active_unit_index := 0

func _ready():
	# Wait one frame so TileMap can spawn units first
	await get_tree().create_timer(0.1).timeout
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

func _start_unit_action(team):
	active_units = active_units.filter(is_instance_valid)

	while active_unit_index < active_units.size():
		var unit = active_units[active_unit_index]

		if not is_instance_valid(unit):
			active_unit_index += 1
			continue

		if team == Team.ENEMY and not unit.is_player:
			print("🤖 Enemy taking turn:", unit.name)

			# 😨 Retreat logic if low HP
			if unit.health < unit.max_health * 0.3:
				print("🩸", unit.name, "is retreating!")

				var retreat_pos = find_safest_tile_away_from_enemies(unit)
				if retreat_pos != Vector2i(-1, -1):
					unit.plan_move(retreat_pos)
					await unit.execute_actions()
					unit_finished_action(unit)
					return

			var tilemap = get_tree().get_current_scene().get_node("TileMap")

			# ✅ Check for adjacent enemies before pathfinding
			if unit.has_method("has_adjacent_enemy") and unit.has_adjacent_enemy():
				print("⚔️ Enemy", unit.name, "has adjacent target. Skipping movement.")
				unit.has_moved = true
				await _run_safe_enemy_action(unit)
				return

			var target = find_weakest_enemy(unit)
			var path = []

			while target:
				path = tilemap.astar.get_point_path(unit.tile_pos, target.tile_pos)

				var has_valid_step = false
				for i in range(1, path.size()):
					var step = path[i]
					if tilemap._is_tile_walkable(step) and not tilemap.is_tile_occupied(step) and not tilemap.is_water_tile(step):
						has_valid_step = true
						break

				if has_valid_step:
					break
				else:
					print("❌ Target", target.name, "is unreachable via land")
					target = find_next_reachable_enemy(unit, [target])

			if target and path.size() > 1:
				print("🎯 Final target:", target.name)
				print("🧭 Path to target:", path)

				var max_steps = min(unit.movement_range, path.size() - 1)
				var next_step: Vector2i = Vector2i(-1, -1)

				for i in range(max_steps, 0, -1):
					var step: Vector2i = path[i]
					if tilemap._is_tile_walkable(step) and not tilemap.is_tile_occupied(step) and not tilemap.is_water_tile(step):
						next_step = step
						break

				if next_step != Vector2i(-1, -1):
					print("🚶 Planning move to:", next_step)
					unit.plan_move(next_step)
				else:
					print("⛔ No valid movement tile found within range")

				if unit.tile_pos.distance_to(target.tile_pos) == 1:
					print("💥 Planning attack on:", target.name)
					unit.plan_attack(target)
				else:
					print("🔎 Target not adjacent yet")
			else:
				print("⛔ No reachable enemies found — skipping unit")

			await unit.execute_actions()
			unit_finished_action(unit)
			return

		elif team == Team.PLAYER and unit.is_player:
			print("🧍 Player unit turn:", unit.name)
			unit.start_turn()
			return

		active_unit_index += 1

	end_turn()

func find_safest_tile_away_from_enemies(unit) -> Vector2i:
	var tilemap = get_tree().get_current_scene().get_node("TileMap")
	var best_tile := Vector2i(-1, -1)
	var best_score := -INF

	for x in range(tilemap.grid_width):
		for y in range(tilemap.grid_height):
			var pos = Vector2i(x, y)

			if not tilemap._is_tile_walkable(pos) or tilemap.is_tile_occupied(pos):
				continue

			var score := 0
			for other in get_tree().get_nodes_in_group("Units"):
				if other == unit or not is_instance_valid(other):
					continue
				if other.is_player != unit.is_player:
					score += pos.distance_squared_to(other.tile_pos)

			if score > best_score:
				best_score = score
				best_tile = pos

	return best_tile

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
	await get_tree().process_frame  # wait for any freed units to process
	active_units = active_units.filter(is_instance_valid)  # clean up
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
