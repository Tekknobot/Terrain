extends Node

var step := 0
var tutorial_active := true
var instruction_label: Label = null

func start():
	step = 0
	tutorial_active = true
	advance()

func advance():
	match step:
		0:
			_set_text("Click Player unit (green) to select it.")
		1:
			_set_text("Click nearby green tile to move.")
		2:
			_set_text("1. Click empty tile to clear selection.\n2. Right-click an enemy to show attack range.")
		3:
			_set_text("1. Click Player 'Tempest' unit.\n2. Right click to arm attack.\n3. Click red tile with or without an enemy to attack.")
		4:
			_set_text("1. Repeat for all units.\n3. Click 'End Turn' to finish your turn.")
		_:
			_set_text("")
			tutorial_active = false

func on_action(action: String):
	if not tutorial_active:
		return

	match step:
		0:
			if action == "unit_selected":
				step += 1
				advance()
		1:
			if action == "unit_moved":
				step += 1
				advance()
		2:
			if action == "attack_range_shown":
				step += 1
				advance()
		3:
			if action == "enemy_attacked":
				step += 1
				advance()
		4:
			if action == "turn_ended":
				step += 1
				advance()

func _set_text(msg: String):
	if instruction_label:
		instruction_label.text = msg
