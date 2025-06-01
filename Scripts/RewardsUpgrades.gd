extends Node2D

# UI elements (adjust paths to match your scene)
@onready var coins_label = $CanvasLayer/Control/Panel/VBoxContainer/HBoxContainer/CoinsLabel
@onready var xp_label = $CanvasLayer/Control/Panel/VBoxContainer/HBoxContainer/XPLabel
@onready var continue_button = $CanvasLayer/Control/Panel/VBoxContainer/ContinueButton
@onready var ability_options_container = $CanvasLayer/Control/Panel/VBoxContainer/AbilityOptionsContainer

@onready var header = $CanvasLayer/Control/Panel/VBoxContainer/Header

var earned_coins: int = 0
var earned_xp: int = 0

# Define the static pool of abilities.
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

# This index is used for cycling through eligible player units.
var next_unit_index: int = 0

# Exported properties for customizing button appearance.
@export var button_min_size: Vector2 = Vector2(200, 64)
@export var button_font: Font = preload("res://Fonts/magofonts/mago2.ttf")  # Adjust the path as needed.

func set_rewards(coins: int, xp: int) -> void:
	self.visible = true
	earned_coins = coins
	earned_xp = xp

	# If no ability assignments exist (the unit_upgrades dictionary is still empty),
	# initialize our dynamic ability pool from the static pool.
	if GameData.unit_upgrades.is_empty():
		GameData.available_abilities = ability_pool.duplicate()
	
	# If there are no available abilities left, skip ability selection.
	if GameData.available_abilities.size() == 0:
		print("All abilities have been assigned; skipping ability selection.")
		#ability_options_container.visible = false
		#_on_continue_button_pressed()
		header.text = "Keep going?"
		return

	# Otherwise, populate the ability buttons using the remaining abilities.
	#_populate_ability_options()


func _ready() -> void:
	#_populate_ability_options()
	continue_button.pressed.connect(_on_continue_button_pressed)

# Utility function to clear the ability container.
func clear_children() -> void:
	for child in ability_options_container.get_children():
		ability_options_container.remove_child(child)
		child.queue_free()

# Populate the container with ability buttons arranged into two rows.
func _populate_ability_options() -> void:
	clear_children()
	
	# Use GameData.available_abilities for the dynamic list.
	var avail_abilities: Array[String] = GameData.available_abilities.duplicate()
	
	# If there are no available abilities, do not populate the container.
	if avail_abilities.size() == 0:
		print("No available abilities remain.")
		ability_options_container.visible = false  # Optionally hide the container.
		# Alternatively, you may automatically proceed:
		#_on_continue_button_pressed()
		return
	
	# Otherwise ensure the container is visible.
	ability_options_container.visible = true

	# Create two HBoxContainers.
	var row1 = HBoxContainer.new()
	row1.custom_minimum_size = Vector2(button_min_size.x * 4, button_min_size.y)
	
	var row2: HBoxContainer = null
	if avail_abilities.size() > 4:
		row2 = HBoxContainer.new()
		row2.custom_minimum_size = Vector2(button_min_size.x * 4, button_min_size.y)
		
	# Create one button per ability.
	for i in range(avail_abilities.size()):
		var ability = avail_abilities[i]
		var btn = Button.new()
		btn.text = ability
		btn.custom_minimum_size = button_min_size  # Set the button's minimum size.
		if button_font:
			btn.add_theme_font_override("font", button_font)
		# Connect the button’s pressed signal to our handler.
		btn.pressed.connect(Callable(self, "_on_ability_pressed").bind(btn, ability))
		
		if i < 4:
			row1.add_child(btn)
		elif row2:
			row2.add_child(btn)
	
	ability_options_container.add_child(row1)
	if row2:
		ability_options_container.add_child(row2)

# Called when an ability button is pressed.
func _on_ability_pressed(btn: Button, ability: String) -> void:
	# Double-check that the ability is still available.
	if not GameData.available_abilities.has(ability):
		print("Ability", ability, "is already assigned.")
		return

	# Obtain eligible player units (those without an assigned ability).
	var eligible_units = get_tree().get_nodes_in_group("Units").filter(
		func(u):
			return u.is_player and (not u.has_meta("special_ability_name") or str(u.get_meta("special_ability_name")).strip_edges() == "")
	)
	if eligible_units.size() == 0:
		print("No eligible units for ability assignment.")
		return

	# Select the next eligible unit.
	var chosen_unit = eligible_units[next_unit_index % eligible_units.size()]
	next_unit_index = (next_unit_index + 1) % eligible_units.size()
	
	print("Assigning ability", ability, "to unit", chosen_unit.name)
	
	# Record the assignment.
	GameData.unit_upgrades[chosen_unit.unit_name] = ability
	chosen_unit.set_meta("special_ability_name", ability)
	# Remove the ability from GameData.available_abilities so it cannot be chosen again.
	GameData.available_abilities.erase(ability)
	
	# Highlight the pressed button with a selected color (e.g., orange).
	var selected_color = Color(1, 0.5, 0, 1)
	btn.add_theme_color_override("font_color", selected_color)
	btn.add_theme_color_override("disabled_font_color", selected_color)
	
	# Deselect and reset the font color on all other buttons.
	for container in ability_options_container.get_children():
		if container is HBoxContainer:
			for other_btn in container.get_children():
				if other_btn is Button and other_btn != btn:
					other_btn.add_theme_color_override("font_color", Color(1, 1, 1, 1))
					other_btn.add_theme_color_override("disabled_font_color", Color(1, 1, 1, 1))
	
	# Disable all ability buttons so no further selection is allowed.
	for container in ability_options_container.get_children():
		if container is HBoxContainer:
			for other_btn in container.get_children():
				if other_btn is Button:
					other_btn.disabled = true
	
	# Proceed immediately (or wait for a user confirmation via continue button).
	#_on_continue_button_pressed()

func _on_continue_button_pressed() -> void:
	GameData.coins += earned_coins
	GameData.xp += earned_xp
	GameData.current_level += 1
	GameData.max_enemy_units += 1
	GameData.map_difficulty += 1
	self.visible = false
	TurnManager.transition_to_next_level()

func _find_unit_by_name(button_name: String) -> Node:
	for u in get_tree().get_nodes_in_group("Units"):
		if u.name == button_name:
			return u
	return null
