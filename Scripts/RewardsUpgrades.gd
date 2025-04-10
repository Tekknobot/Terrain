extends Node2D

# UI elements (adjust paths to match your scene)
@onready var coins_label = $CanvasLayer/Control/VBoxContainer/HBoxContainer/CoinsLabel
@onready var xp_label = $CanvasLayer/Control/VBoxContainer/HBoxContainer/XPLabel
@onready var continue_button = $CanvasLayer/Control/VBoxContainer/ContinueButton
@onready var ability_options_container = $CanvasLayer/Control/VBoxContainer/AbilityOptionsContainer

var earned_coins: int = 0
var earned_xp: int = 0

# Define a pool of special abilities available for unlocking.
var ability_pool: Array[String] = [
	"Overcharge",  
	"Critical Strike", 
	"Rapid Fire",  
	"Healing Wave",
	"Explosive Rounds",    
	"Spider Blast",
	"Thread Attack",
	"Lightning Surge"
]

# This array tracks which abilities have already been assigned.
var used_abilities: Array[String] = []
# This index is used for cycling through eligible player units.
var next_unit_index: int = 0

# Exported properties to pick the button size and font.
@export var button_min_size: Vector2 = Vector2(200, 64)
@export var button_font: Font = preload("res://Fonts/magofonts/mago2.ttf")  # Change the path accordingly.

func set_rewards(coins: int, xp: int) -> void:
	self.visible = true
	earned_coins = coins
	earned_xp = xp
	_populate_ability_options()

func _ready() -> void:
	# Only call _populate_ability_options() here if set_rewards() isn't called afterward.
	# If set_rewards() is always called externally, you can remove this call.
	#_populate_ability_options()
	continue_button.pressed.connect(_on_continue_button_pressed)

func _populate_ability_options() -> void:
	# Create two HBoxContainers. The first will always be created.
	var row1 = HBoxContainer.new()
	# Set a minimum size on row1 if needed.
	row1.custom_minimum_size = Vector2(button_min_size.x * 4, button_min_size.y)
	
	# Create a second row only if there are more than 4 abilities.
	var row2: HBoxContainer = null
	if ability_pool.size() > 4:
		row2 = HBoxContainer.new()
		row2.custom_minimum_size = Vector2(button_min_size.x * 4, button_min_size.y)
	# Now iterate over the abilities.
	for i in range(ability_pool.size()):
		var ability = ability_pool[i]
		var btn = Button.new()
		btn.text = ability
		btn.custom_minimum_size = button_min_size  # Set the button's minimum size.
		if button_font:
			btn.add_theme_font_override("font", button_font)
		# Connect the button's pressed signal to our handler, passing this button and its ability.
		btn.pressed.connect(Callable(self, "_on_ability_pressed").bind(btn, ability))
		
		# Add the button to row1 if it's one of the first four, otherwise to row2.
		if i < 4:
			row1.add_child(btn)
		elif row2:
			row2.add_child(btn)
	# Add the rows to the ability_options_container.
	ability_options_container.add_child(row1)
	if row2:
		ability_options_container.add_child(row2)


# Called when an ability button is pressed.
func _on_ability_pressed(btn: Button, ability: String) -> void:
	# If this ability is already used on any unit, do not allow re‑assignment.
	if ability in used_abilities:
		print("Ability", ability, "is already assigned.")
		return

	# Obtain eligible player units (ones that do not have an assigned ability).
	var eligible_units = get_tree().get_nodes_in_group("Units").filter(
		func(u):
			return u.is_player and (not u.has_meta("special_ability_name") or str(u.get_meta("special_ability_name")).strip_edges() == "")
	)

	if eligible_units.size() == 0:
		print("No eligible units for ability assignment.")
		return

	# Select the next eligible unit based on next_unit_index.
	var chosen_unit = eligible_units[next_unit_index % eligible_units.size()]
	next_unit_index = (next_unit_index + 1) % eligible_units.size()

	print("Assigning ability", ability, "to unit", chosen_unit.name)
	# Record the assignment in GameData.
	GameData.unit_upgrades[chosen_unit.unit_name] = ability
	# Store the ability on the unit using metadata.
	chosen_unit.set_meta("special_ability_name", ability)
	used_abilities.append(ability)

	# Trigger any visual or audio level-up effect on the chosen unit.
	if chosen_unit.has_method("play_level_up_effect"):
		chosen_unit.play_level_up_effect()
	elif chosen_unit.has_method("play_level_up_sound"):
		chosen_unit.play_level_up_sound()
	elif chosen_unit.has_method("apply_level_up_material"):
		chosen_unit.apply_level_up_material()

	# Disable all ability buttons so further selection is not allowed.
	for child in ability_options_container.get_children():
		if child is Button:
			child.disabled = true

	# Immediately proceed.
	_on_continue_button_pressed()

func _on_continue_button_pressed() -> void:
	GameData.coins += earned_coins
	GameData.xp += earned_xp
	GameData.current_level += 1
	GameData.max_enemy_units += 1
	GameData.map_difficulty += 1
	self.visible = false
	TurnManager.transition_to_next_level()

func _find_unit_by_name(button_name: String) -> Node:
	# Iterate through the "Units" group and return the unit whose name matches the button name.
	for u in get_tree().get_nodes_in_group("Units"):
		if u.name == button_name:
			return u
	return null
