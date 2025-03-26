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
	emit_signal("turn_started", team)
	_start_unit_action(team)

func _start_unit_action(team):
	# Keep advancing until we find a unit of the correct team
	while active_unit_index < active_units.size():
		var unit = active_units[active_unit_index]
		if unit.is_player == (team == Team.PLAYER):
			unit.start_turn()
			return
		active_unit_index += 1

	# No more units for this team → end turn
	end_turn()

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
