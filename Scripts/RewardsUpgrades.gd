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
	"Critical Strike", 
	"Rapid Fire",  
	"Healing Wave",
	"Explosive Rounds",	
	"Spider Blast"	
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
	#coins_label.text = "Coins Earned: %d" % coins
	#xp_label.text = "XP Earned: %d" % xp
	_populate_ability_options()

func _populate_ability_options() -> void:
	for ability in ability_pool:
		var btn = Button.new()
		btn.text = ability
		btn.custom_minimum_size = Vector2(0, 64)  # Set minimum height to 64 pixels.
		btn.pressed.connect(self._on_ability_selected.bind(btn, ability))
		ability_options_container.add_child(btn)

# Called when a special ability is selected.
func _on_ability_selected(btn: Button, ability: String) -> void:
	# If an ability is already selected, exit early.
	if selected_ability != "":
		print("An ability has already been selected.")
		return

	print("Special Ability selected: ", ability)
	
	# Check if the ability is already assigned to any unit.
	if ability in GameData.unit_upgrades.values():
		print("Ability ", ability, " is already assigned to a unit. It cannot be assigned again.")
		return  # Do not assign the ability again.

	selected_ability = ability
	GameData.selected_special_ability = ability

	# Unhighlight all ability buttons.
	for child in ability_options_container.get_children():
		if child is Button:
			child.modulate = Color(1, 1, 1)
	# Highlight the selected button.
	btn.modulate = Color(0.7, 0.7, 1.0)

	# Filter eligible units: only include player units that do NOT already have an ability.
	var eligible_units = get_tree().get_nodes_in_group("Units").filter(func(u):
		return u.is_player and (not u.has_meta("special_ability_name") or str(u.get_meta("special_ability_name")).strip_edges() == "")
	)
	
	if eligible_units.size() > 0:
		# Cycle through eligible units using the next_unit_index.
		var chosen_unit = eligible_units[next_unit_index % eligible_units.size()]
		next_unit_index = (next_unit_index + 1) % eligible_units.size()
		print("Assigning ability ", ability, " to unit: ", chosen_unit.name)
		
		# Apply the special ability to the chosen unit using metadata.
		apply_special_ability(chosen_unit, ability)
		
		# Record this upgrade in GameData so that future spawns get this ability.
		GameData.unit_upgrades[chosen_unit.unit_name] = ability
		
		# Trigger the unit level-up effect.
		if chosen_unit.has_method("play_level_up_effect"):
			chosen_unit.play_level_up_effect()
		else:
			if chosen_unit.has_method("play_level_up_sound"):
				chosen_unit.play_level_up_sound()
			if chosen_unit.has_method("apply_level_up_material"):
				chosen_unit.apply_level_up_material()
				
		# Disable further selection by disabling all ability buttons.
		for child in ability_options_container.get_children():
			if child is Button:
				child.disabled = true
	else:
		print("No eligible units to receive a new ability upgrade.")

	_on_continue_button_pressed()
				
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
	TurnManager.transition_to_next_level()

func apply_special_ability(unit, ability: String) -> void:
	unit.set_meta("special_ability_name", ability)
	print("Applied special ability (via meta): ", ability, " to unit: ", unit.name)
