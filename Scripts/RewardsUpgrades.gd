# RewardUpgrade.gd
extends Node2D

@onready var coins_label = $CanvasLayer/Control/VBoxContainer/HBoxContainer/CoinsLabel
@onready var xp_label = $CanvasLayer/Control/VBoxContainer/HBoxContainer/XPLabel
@onready var upgrade_options_container = $CanvasLayer/Control/VBoxContainer/UpgradeOptionsContainer
@onready var continue_button = $CanvasLayer/Control/VBoxContainer/ContinueButton

var earned_coins: int = 0
var earned_xp: int = 0

# Call this function to initialize reward data from your battle stats.
func set_rewards(coins: int, xp: int) -> void:
	self.visible = true
	earned_coins = coins
	earned_xp = xp
	coins_label.text = "Coins Earned: %d" % coins
	xp_label.text = "XP Earned: %d" % xp
	_populate_upgrade_options()

# Populate available upgrade options.
func _populate_upgrade_options() -> void:
	var upgrade_options = ["+Health", "+Damage", "+Move"]
	for option in upgrade_options:
		var btn = Button.new()
		btn.text = option
		# Bind both the button and the option to the pressed signal.
		btn.pressed.connect(self._on_upgrade_selected.bind(btn, option))
		upgrade_options_container.add_child(btn)

# Called when an upgrade option is selected.
func _on_upgrade_selected(btn: Button, option: String) -> void:
	print("Upgrade selected: ", option)
	# Save the choice in your global singleton.
	GameData.selected_upgrade = option

	# Unhighlight all buttons.
	for child in upgrade_options_container.get_children():
		if child is Button:
			# Reset the button's appearance. (Adjust the default color as needed.)
			child.modulate = Color(1, 1, 1)

	# Highlight the selected button.
	btn.modulate = Color(0.7, 0.7, 1.0)  # This gives a bluish tint; adjust to your taste.


# When the player is ready to proceed.
func _on_continue_button_pressed() -> void:
	# Here you can update persistent data with the earned rewards.
	GameData.coins += earned_coins
	GameData.xp += earned_xp

	# Save the current level progress if needed.
	GameData.current_level += 1
	GameData.max_enemy_units += 1
	GameData.map_difficulty += 1
	
	self.visible = false
	
	# Transition to the next mission/level.
	get_tree().change_scene_to_file("res://Scenes/Main.tscn")
