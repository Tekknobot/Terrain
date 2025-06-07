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
			_set_text("Click green player unit to select it.")
		1:
			_set_text("Click nearby green tile to move.")
		2:
			_set_text("1. Click empty tile to clear selection.\n2. Right-click an enemy to show attack range.")
		3:
			_set_text("1. Click player 'Tempest' unit.\n2. Right click to arm attack.\n3. Click red tile with or without an enemy to attack.")
		4:
			_set_text("1. Repeat for all units.\n3. Click 'End Turn' to finish your turn.")
		5:	
			_set_text("Tip: Utilize the push mechanic.")		
		6:
			_set_text("Tip: Destroy unit with collision.")	
		7:
			_set_text("Tip: Tip: Destroy unit by pushing it off grid.")	
		8:	
			_set_text("Tip: Level up with direct hits.")										
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
		5:
			if action == "push_mechanic":
				step += 1
				advance()
		6:
			if action == "collide_mechanic":
				step += 1
				advance()				
		7:
			if action == "offgrid_mechanic":
				step += 1
				advance()	
		8:
			if action == "leveled_up":
				step += 1
				advance()
												
func _set_text(msg: String):
	if instruction_label:
		instruction_label.text = msg
