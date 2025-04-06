extends Node2D

@onready var coins_label = $CanvasLayer/Control/VBoxContainer/HBoxContainer/CoinsLabel
@onready var xp_label = $CanvasLayer/Control/VBoxContainer/HBoxContainer/XPLabel
@onready var ability_options_container = $CanvasLayer/Control/VBoxContainer/AbilityOptionsContainer
@onready var continue_button = $CanvasLayer/Control/VBoxContainer/ContinueButton

var earned_coins: int = 0
var earned_xp: int = 0

# Define a pool of special abilities available for unlocking.
var ability_pool: Array[String] = [
	"Overcharge", 
	"Shield Boost", 
	"Critical Strike", 
	"Rapid Fire", 
	"Explosive Rounds", 
	"Healing Wave"
]

# Store the player's selection.
var selected_ability: String = ""
# Cycle index to assign ability to each player unit in turn.
var next_unit_index: int = 0

# Called when the reward screen is activated.
func set_rewards(coins: int, xp: int) -> void:
	self.visible = true
	earned_coins = coins
	earned_xp = xp
	coins_label.text = "Coins Earned: %d" % coins
	xp_label.text = "XP Earned: %d" % xp
	_populate_ability_options()

# Populate the container with a button for each special ability.
func _populate_ability_options() -> void:
	for ability in ability_pool:
		var btn = Button.new()
		btn.text = ability
		# Bind both the button and ability so that when pressed, the handler receives both.
		btn.pressed.connect(self._on_ability_selected.bind(btn, ability))
		ability_options_container.add_child(btn)

# Called when a special ability is selected.
func _on_ability_selected(btn: Button, ability: String) -> void:
	print("Special Ability selected: ", ability)
	selected_ability = ability
	GameData.selected_special_ability = ability

	# Unhighlight all ability buttons.
	for child in ability_options_container.get_children():
		if child is Button:
			child.modulate = Color(1, 1, 1)
	# Highlight the selected button.
	btn.modulate = Color(0.7, 0.7, 1.0)

	# Cycle through each player unit (instead of a random selection).
	var player_units = get_tree().get_nodes_in_group("Units").filter(func(u): return u.is_player)
	if player_units.size() > 0:
		var chosen_unit = player_units[next_unit_index]
		# Update the index for next selection (wrap around if needed).
		next_unit_index = (next_unit_index + 1) % player_units.size()
		print("Assigning ability ", ability, " to unit: ", chosen_unit.name)
		# Apply the special ability to the chosen unit.
		apply_special_ability(chosen_unit, ability)
		# Trigger the unit level-up effect.
		if chosen_unit.has_method("play_level_up_effect"):
			chosen_unit.play_level_up_effect()
		else:
			# Fallback: play level-up sound and material effect if available.
			if chosen_unit.has_method("play_level_up_sound"):
				chosen_unit.play_level_up_sound()
			if chosen_unit.has_method("apply_level_up_material"):
				chosen_unit.apply_level_up_material()
# Called when the player presses the Continue button.
func _on_continue_button_pressed() -> void:
	# Update persistent data with the earned rewards.
	GameData.coins += earned_coins
	GameData.xp += earned_xp
	GameData.current_level += 1
	GameData.max_enemy_units += 1
	GameData.map_difficulty += 1
	
	# Optionally, apply the selected special ability to a unit.
	# For example, if you have a reference to the unit that should receive the upgrade:
	# apply_special_ability(upgraded_unit, selected_ability)
	
	self.visible = false
	# Transition to the next mission/level.
	get_tree().change_scene_to_file("res://Scenes/Main.tscn")

func apply_special_ability(unit, ability: String) -> void:
	unit.set_meta("special_ability_name", ability)
	print("Applied special ability (via meta): ", ability, " to unit: ", unit.name)
