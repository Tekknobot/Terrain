# TurnManager.gd
extends Node

signal turn_started(current_team)
signal turn_ended(current_team)
signal round_ended(ended_team : int)

enum Team { ENEMY, PLAYER }

var turn_order = [Team.PLAYER, Team.ENEMY]
var current_turn_index := 0
var active_units := []
var active_unit_index := 0

var initial_player_unit_count: int = 6
var total_damage_dealt: int = 0

var current_transition: Node = null  # Member variable to store the active transition.

var next_unit_id: int = 1
var match_done: bool = false

@export var reset_button: Button
const AI_SPECIAL_CHANCE := 60  # percent chance to actually fire a special when one is available

func _ready():
	# Record the initial number of player units.
	initial_player_unit_count = get_tree().get_nodes_in_group("Units").filter(func(u): return u.is_player).size()

	# Wait one frame so TileMap can spawn units first
	await get_tree().create_timer(0.5).timeout
	call_deferred("_initialize_turns")
	#_test_launch_reward_phase()

func _initialize_turns():
	_populate_units()
	#print("TurnManager loaded units:", active_units.size(), active_units)
	#start_turn()

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
			reset_button.visible = false
		
		var stats = {
			"units_lost": calculate_units_lost(),
			"damage_dealt": calculate_damage_dealt()
		}
		var rewards = {
			"xp": calculate_xp_reward(),
			"coins": calculate_coins_reward()
		}
		
		_show_game_over_screen(result, stats, rewards)
		
		print("🏁 Game Over — no units remain for one team. Turn will not start.")
		return

	var team_name = "UNKNOWN"
	if team == Team.PLAYER:
		team_name = "PLAYER"
	elif team == Team.ENEMY:
		team_name = "ENEMY"
	
	print("🔁 Starting turn for:", team_name)
	
	emit_signal("turn_started", team)
	
	await _start_unit_action(team)

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
	# 1) Wait for any “being_pushed” to clear
	while true:
		var still_pushing = false
		for u in get_tree().get_nodes_in_group("Units"):
			if is_instance_valid(u) and u.being_pushed:
				still_pushing = true
				break
		if not still_pushing:
			break
		await get_tree().process_frame

	active_units = active_units.filter(is_instance_valid)
	var tilemap = get_tree().get_current_scene().get_node("TileMap")

	# 2) Find the next unit for this team
	while active_unit_index < active_units.size():
		var unit = active_units[active_unit_index]
		if not is_instance_valid(unit):
			active_unit_index += 1
			continue

		# ─── ENEMY TURN ─────────────────────────────────────────
		if team == Team.ENEMY and not unit.is_player:
			hide_end_turn_button()

			# a) Only try a special if we haven't yet moved or attacked
			if not unit.has_moved and not unit.has_attacked:
				var special = _choose_special_ability(unit)
				if special and (randi() % 100) < AI_SPECIAL_CHANCE:
					match special.ability:
						"ground_slam":
							tilemap.request_ground_slam(unit.unit_id, special.target)
						"mark_and_pounce":
							tilemap.request_mark_and_pounce(unit.unit_id, special.target.get_meta("unit_id"))
						"guardian_halo":
							tilemap.request_guardian_halo(unit.unit_id, special.target)
						"high_arcing_shot":
							tilemap.request_high_arcing_shot(unit.unit_id, special.target)
						"suppressive_fire":
							tilemap.request_suppressive_fire(unit.unit_id, special.target)
						"fortify":
							tilemap.request_fortify(unit.unit_id, special.target)
						"request_airlift_pick":
							tilemap.request_heavy_rain(unit.unit_id, special.target)
						"spider_blast":
							tilemap.request_thread_attack(unit.unit_id, special.target)
						# …add any other specials you’ve defined here…
					await unit.execute_actions()
					unit.has_moved = true
					unit.has_attacked = true
					unit_finished_action(unit)
					return

			# b) Otherwise, plan movement toward closest enemy
			var target = find_closest_enemy(unit)
			if target:
				tilemap.update_astar_grid()
				var path = await unit.compute_path(unit.tile_pos, target.tile_pos)
				if path.size() > 1:
					var move_tile: Vector2i = unit.tile_pos
					var max_dist := -1
					if is_instance_valid(target):
						for i in range(1, min(unit.movement_range + 1, path.size())):
							var world_point: Vector2 = path[i]
							var tile_point = Vector2i(int(world_point.x), int(world_point.y))
							var d = tile_point.distance_to(target.tile_pos)
							if d <= unit.attack_range and d > 1 and d > max_dist:
								max_dist = d
								move_tile = tile_point
					if move_tile == unit.tile_pos and path.size() > 1:
						var fallback = path[min(unit.movement_range, path.size() - 1)]
						move_tile = Vector2i(int(fallback.x), int(fallback.y))
					unit.plan_move(move_tile)

			# execute movement
			await unit.execute_actions()
			if not is_instance_valid(unit):
				end_turn()

			# c) Ranged vs melee fallback attack
			if unit.unit_type in ["Ranged", "Support"]:
				var rt = _find_ranged_target(unit)
				if rt:
					tilemap.request_auto_attack_ranged_unit(unit.unit_id, rt.unit_id)
			elif unit.has_method("has_adjacent_enemy") and unit.has_adjacent_enemy():
				await unit.auto_attack_adjacent()

			unit_finished_action(unit)
			return

		# ─── PLAYER TURN ────────────────────────────────────────
		elif team == Team.PLAYER and unit.is_player:
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
		await _start_unit_action(turn_order[current_turn_index])
		end_turn()
		return

	await unit.execute_actions()
	if not is_instance_valid(unit):
		end_turn()
		return
	
	if is_instance_valid(unit):
		unit_finished_action(unit)
	else:
		print("☠️ Unit died during execution. Skipping.")
		active_unit_index += 1
		await get_tree().process_frame
		await _start_unit_action(turn_order[current_turn_index])
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

func end_turn(game_over: bool = false):
	show_end_turn_button()
	
	# Hide the HUD whenever the enemy turn starts
	if turn_order[current_turn_index] == Team.PLAYER:
		var hud = get_node("/root/BattleGrid/HUDLayer/Control")
		hud.visible = false
			
	# 🧾 Gather battle stats
	var stats = {
		"units_lost": calculate_units_lost(),
		"damage_dealt": calculate_damage_dealt()
	}
	var rewards = {
		"xp": calculate_xp_reward(),
		"coins": calculate_coins_reward()
	}

	# 🧠 Check victory conditions
	var player_units_exist := false
	var enemy_units_exist := false
	for u in get_tree().get_nodes_in_group("Units"):
		if u.is_player:
			player_units_exist = true
		else:
			enemy_units_exist = true

	if not player_units_exist:
		print("❌ Game Over - You Lost!")
		_show_game_over_screen("lose", stats, rewards)
		hide_end_turn_button()
		match_done = true
		return
	elif not enemy_units_exist:
		print("✅ Game Over - You Won!")
		_show_game_over_screen("win", stats, rewards)
		hide_end_turn_button()
		_launch_reward_phase(rewards)  # 🔥 Show upgrade screen
		match_done = true
		
		# Hide reset button
		var reset_button = get_tree().get_nodes_in_group("Reset_Button")
		reset_button[0].visible = false
				
		return

	# 🔁 Emit turn-end signals
	emit_signal("turn_ended", turn_order[current_turn_index])
	# end of a full round happens when the ENEMY just finished
	if turn_order[current_turn_index] == Team.ENEMY:
		emit_signal("round_ended", turn_order[current_turn_index])

	if game_over:
		print("🏁 Game Over flag set — skipping next turn.")
		return

	# 🔁 Recheck for unit existence to prevent edge cases
	player_units_exist = false
	enemy_units_exist = false
	for u in get_tree().get_nodes_in_group("Units"):
		if u.is_player:
			player_units_exist = true
		else:
			enemy_units_exist = true

	if not player_units_exist or not enemy_units_exist:
		print("🏁 No units left — skipping further turns.")
		return

	# 🧠 Enemy turn: spawn new units
	if turn_order[current_turn_index] == Team.ENEMY:
		var tilemap = get_tree().get_current_scene().get_node("TileMap")
		tilemap.spawn_new_enemy_units()
		_populate_units()

	# 🔁 Cycle to next team
	current_turn_index = (current_turn_index + 1) % turn_order.size()
	active_unit_index = 0

	call_deferred("start_turn")

	# 💡 Reset any highlights
	var tilemap = get_tree().get_current_scene().get_node("TileMap")
	tilemap._clear_highlights()

func hide_end_turn_button() -> void:
	var end_turn_button = get_tree().get_current_scene().get_node("CanvasLayer/Control/HBoxContainer/EndTurn")
	if end_turn_button:
		end_turn_button.visible = false
		pass
	else:
		print("EndTurn button not found!")

func show_end_turn_button() -> void:
	var end_turn_button = get_tree().get_current_scene().get_node("CanvasLayer/Control/HBoxContainer/EndTurn")
	if end_turn_button:
		end_turn_button.visible = true
		pass
	else:
		print("EndTurn button not found!")

func unit_finished_action(unit):
	active_unit_index += 1
	await get_tree().process_frame  # Wait for any pending updates
	active_units = active_units.filter(is_instance_valid)
	await _start_unit_action(turn_order[current_turn_index])

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
	GameData.first_enemy_spawn_done = false
	# Optionally, reset initial_player_unit_count here if needed.
	initial_player_unit_count = get_tree().get_nodes_in_group("Units").filter(
		func(u): return u.is_player
	).size()
	print("Match stats reset!")

func _launch_reward_phase(rewards: Dictionary):
	var reward_scene = preload("res://Prefabs/UpgradeWindow.tscn")
	var reward_ui = reward_scene.instantiate()
	get_tree().get_current_scene().add_child(reward_ui)
	reward_ui.set_rewards()

func _test_launch_reward_phase() -> void:
	var fake_rewards: Dictionary = {
		"coins": 100,
		"xp": 50
	}
	_launch_reward_phase(fake_rewards)

func transition_to_next_level() -> void:
	var transition_scene = preload("res://Scenes/Transition.tscn")
	var transition = transition_scene.instantiate()
	# Optionally, add to a dedicated overlay layer if available.
	var overlay_layer = get_tree().get_current_scene().get_node("OverlayLayer")
	if overlay_layer:
		overlay_layer.add_child(transition)
	else:
		get_tree().get_current_scene().add_child(transition)
	
	# Ensure the transition is fully opaque before starting (if needed).
	transition.fade_duration = 2
	
	# Fade out the current scene.
	var tween = transition.fade_out()
	tween.connect("finished", Callable(self, "_on_fade_out_finished"))

func transition_to_level() -> void:
	var transition_scene = preload("res://Scenes/Transition.tscn")
	var transition = transition_scene.instantiate()
	# Optionally, add to a dedicated overlay layer if available.
	var overlay_layer = get_tree().get_current_scene().get_node("OverlayLayer")
	if overlay_layer:
		overlay_layer.add_child(transition)
	else:
		get_tree().get_current_scene().add_child(transition)
	
	# Ensure the transition is fully opaque before starting (if needed).
	transition.modulate.a = 1.0
	transition.fade_duration = 2
	
	# Fade in the current scene by gradually making the transition transparent.
	var tween = transition.fade_in()
	
func _on_fade_out_finished() -> void:
	# Change to the next level/mission.
	var next_scene_path = "res://Scenes/Main.tscn"  # or the desired next scene
	var err = get_tree().change_scene_to_file(next_scene_path)
	if err != OK:
		print("Error changing scene!")
	
	# Optionally, wait a short time before fading in.
	await get_tree().create_timer(0.1).timeout
	
	# Now instantiate a fresh Transition node for the fade in.
	var transition_scene = preload("res://Scenes/Transition.tscn")
	var new_transition = transition_scene.instantiate()
	get_tree().get_current_scene().add_child(new_transition)
	new_transition.fade_in()

# Generates a Manhattan path from 'start' to 'end' that only uses horizontal and vertical moves.
func manhattan_line(start: Vector2i, end: Vector2i) -> Array:
	var path = []
	var current = Vector2i(start.x, start.y)
	path.append(current)
	
	var dx = end.x - start.x
	var dy = end.y - start.y
	
	var step_x := 0
	if dx > 0:
		step_x = 1
	elif dx < 0:
		step_x = -1
	
	var step_y := 0
	if dy > 0:
		step_y = 1
	elif dy < 0:
		step_y = -1
	
	var moves = []
	# Append horizontal moves.
	var abs_dx = abs(dx)
	for i in range(abs_dx):
		moves.append("H")
	# Append vertical moves.
	var abs_dy = abs(dy)
	for i in range(abs_dy):
		moves.append("V")
	
	# Shuffle the moves array randomly to vary the Manhattan path.
	for i in range(moves.size()):
		var j = randi() % moves.size()
		var temp = moves[i]
		moves[i] = moves[j]
		moves[j] = temp
	
	# Follow the moves.
	for move in moves:
		if move == "H":
			current.x += step_x
		elif move == "V":
			current.y += step_y
		path.append(Vector2i(current.x, current.y))
		
	return path

func _choose_special_ability(unit):
	var tilemap = get_tree().get_current_scene().get_node("TileMap")
	var directions = [
		Vector2i( 1,  0), Vector2i(-1,  0),
		Vector2i( 0,  1), Vector2i( 0, -1)
	]

	# 1) Hulk — Ground Slam
	if unit.unit_name == "Vanguard":
		for dir in directions:
			var check = unit.tile_pos + dir
			if tilemap.is_within_bounds(check):
				var u = tilemap.get_unit_at_tile(check)
				if u and u.is_player:
					return {
						"ability": "ground_slam",
						"target": check
					}

	# 2) Panther — Mark & Pounce
	if unit.unit_name == "Aegis":
		for other in get_tree().get_nodes_in_group("Units"):
			if other.is_player:
				var dist = abs(unit.tile_pos.x - other.tile_pos.x) + abs(unit.tile_pos.y - other.tile_pos.y)
				if dist > 0 and dist <= 3:
					return {
						"ability": "mark_and_pounce",
						"target": other
					}

	# 3) Angel — Guardian Halo
	if unit.unit_name == "Tempest":
		var best_ally = null
		var lowest_hp = INF
		for u in get_tree().get_nodes_in_group("Units"):
			if u.is_player == unit.is_player and u != unit:
				var d = abs(unit.tile_pos.x - u.tile_pos.x) + abs(unit.tile_pos.y - u.tile_pos.y)
				if d <= 5 and u.health < lowest_hp:
					lowest_hp = u.health
					best_ally = u
		if best_ally and best_ally.health < best_ally.max_health * 0.7:
			return {
				"ability": "guardian_halo",
				"target": best_ally.tile_pos
			}

	# 4) Cannon — High‑Arcing Shot
	if unit.unit_name == "Titan":
		var best_center = null
		var best_count = 0
		for other in get_tree().get_nodes_in_group("Units"):
			if other.is_player:
				var center = other.tile_pos
				var d = abs(unit.tile_pos.x - center.x) + abs(unit.tile_pos.y - center.y)
				if d <= 5:
					var count = 0
					for dx in range(-1, 2):
						for dy in range(-1, 2):
							var t = Vector2i(center.x + dx, center.y + dy)
							if tilemap.is_within_bounds(t):
								var u = tilemap.get_unit_at_tile(t)
								if u and u.is_player:
									count += 1
					if count > best_count:
						best_count = count
						best_center = center
		if best_center != null and best_count > 1:
			return {
				"ability": "high_arcing_shot",
				"target": best_center
			}

	# 5) MultiTurret — Suppressive Fire
	if unit.unit_name == "Specter":
		for dir in directions:
			var check = unit.tile_pos + dir
			if tilemap.is_within_bounds(check):
				var u = tilemap.get_unit_at_tile(check)
				if u and u.is_player:
					return {
						"ability": "suppressive_fire",
						"target": unit.tile_pos
					}

	# 6) Brute — Fortify (self‑buff)
	if unit.unit_name == "Nova":
		if not unit.is_fortified:
			return {
				"ability": "fortify",
				"target": unit.tile_pos   # ← now we supply one Vector2i
			}

	# 7) Helicopter — Heavy Rain (5×5 AOE within 5)
	if unit.unit_name == "Raptor":
		var best_center := Vector2i(-1, -1)
		var best_count := 0
		# scan every player unit as a candidate center
		for other in get_tree().get_nodes_in_group("Units"):
			if other.is_player:
				var center = other.tile_pos
				var d = abs(unit.tile_pos.x - center.x) + abs(unit.tile_pos.y - center.y)
				if d <= 5:
					# count how many enemies in a 5×5 around this center
					var count := 0
					for dx in range(-2, 3):  # -2, -1, 0, 1, 2
						for dy in range(-2, 3):
							var t = Vector2i(center.x + dx, center.y + dy)
							if tilemap.is_within_bounds(t):
								var u = tilemap.get_unit_at_tile(t)
								if u and u.is_player:
									count += 1
					if count > best_count:
						best_count = count
						best_center = center

		# only cast if we'll hit at least one target
		if best_center != Vector2i(-1, -1) and best_count > 0:
			return {
				"ability": "request_heavy_rain",
				"target": best_center
			}

	# 8) Spider — Spider Blast
	if unit.unit_name == "Valkyrie":
		for other in get_tree().get_nodes_in_group("Units"):
			if other.is_player:
				var d = abs(unit.tile_pos.x - other.tile_pos.x) + abs(unit.tile_pos.y - other.tile_pos.y)
				if d <= 5:
					return {
						"ability": "spider_blast",
						"target": other.tile_pos
					}

	# no special chosen
	return null
