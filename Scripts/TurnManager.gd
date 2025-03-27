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
	while active_unit_index < active_units.size():
		var unit = active_units[active_unit_index]

		if not is_instance_valid(unit):
			active_unit_index += 1
			continue

		if team == Team.ENEMY and not unit.is_player:
			print("🤖 Enemy taking turn:", unit.name)

			var tilemap = get_tree().get_current_scene().get_node("TileMap")
			var target = find_closest_enemy(unit)

			var path = []
			while target:
				path = tilemap.astar.get_point_path(unit.tile_pos, target.tile_pos)

				# Check if there's any dry step along the way
				var has_valid_step = false
				for i in range(1, path.size()):
					var step = path[i]
					if tilemap._is_tile_walkable(step) and not tilemap.is_tile_occupied(step) and not tilemap.is_water_tile(step):
						has_valid_step = true
						break

				if has_valid_step:
					break  # ✅ We found a reachable target
				else:
					print("❌ Target", target.name, "is unreachable via land")
					target = find_next_reachable_enemy(unit, [target])

			# If we have a reachable target and path
			if target and path.size() > 1:
				print("🎯 Final target:", target.name)
				print("🧭 Path to target:", path)

				# Find the furthest valid step within movement range
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
	_start_unit_action(turn_order[current_turn_index])

func find_closest_enemy(unit) -> Node:
	var closest: Node = null
	var shortest: float = INF

	for u in get_tree().get_nodes_in_group("Units") as Array:
		if u.is_player != unit.is_player:
			var dist: float = unit.tile_pos.distance_to(u.tile_pos)
			if dist < shortest:
				shortest = dist
				closest = u

	return closest
