# File: res://Scenes/RewardUpgrade.gd
extends CanvasLayer

@export var upgrade_options := [
	"hp_boost",
	"damage_boost",
	"range_boost",
	"move_boost",
]

@export var label_font: Font  # Custom font for labels
@export var button_font: Font  # Custom font for buttons
@export var panel_offset: Vector2 = Vector2.ZERO  # Manual offset from screen center

var chosen_upgrades: Dictionary = {}  # unit_id: selected_upgrade
var _units_to_choose: int = 0

func _ready():
	_center_panel_with_offset()

func _center_panel_with_offset():
	await get_tree().process_frame
	var panel = $Control/PanelContainer
	if panel:
		panel.anchor_left = 0.5
		panel.anchor_top = 0.5
		panel.anchor_right = 0.5
		panel.anchor_bottom = 0.5
		panel.pivot_offset = panel.size / 2
		panel.position = panel_offset

# Call this with coins and xp after victory
func set_rewards():
	var panel = $Control/PanelContainer
	panel.visible = false
	await get_tree().create_timer(1).timeout 
	panel.visible = true
	# Populate fresh choices
	_display_unit_choices()

func _display_unit_choices():
	var units = get_tree().get_nodes_in_group("Units").filter(func(u):
		return u.is_player and is_instance_valid(u)
	)

	_units_to_choose = units.size()

	for unit in units:
		var unit_id = unit.unit_id
		var name = unit.unit_name
		var vbox = VBoxContainer.new()
		vbox.name = str(unit_id)

		# Portrait
		if unit.portrait:
			var portrait = TextureRect.new()
			portrait.texture = unit.portrait
			portrait.expand_mode = TextureRect.EXPAND_KEEP_SIZE
			portrait.stretch_mode = TextureRect.STRETCH_SCALE
			portrait.size = Vector2(64, 64)
			vbox.add_child(portrait)

		# Build your upgrade list, but drop range_boost on melee-only units
		var options = upgrade_options.duplicate()
		if unit.unit_type == "Melee":
			options.erase("range_boost")
		if unit.unit_type == "Ranged" or unit.unit_type == "Support":
			options.erase("damage_boost")			
			
		options.shuffle()

		# Now pick the first three (you’ll always have at least 3 left,
		# since the full list starts at 4)
		for i in range(3):
			var upgrade = options[i]
			var btn = Button.new()
			btn.text = upgrade
			if button_font:
				btn.add_theme_font_override("font", button_font)
			btn.pressed.connect(Callable(self, "_on_upgrade_chosen").bind(unit_id, upgrade))
			vbox.add_child(btn)

		$Control/PanelContainer/MarginContainer/VBoxContainer/UpgradeContainer.add_child(vbox)

func _on_upgrade_chosen(unit_id: int, upgrade: String):
	if chosen_upgrades.has(unit_id):
		return

	chosen_upgrades[unit_id] = upgrade
	_apply_upgrade_to_unit(unit_id, upgrade)

	# Gray out buttons
	var vbox = $Control/PanelContainer/MarginContainer/VBoxContainer/UpgradeContainer.get_node(str(unit_id))
	for child in vbox.get_children():
		if child is Button:
			child.disabled = true

	# Once all chosen, close UI and return
	if chosen_upgrades.size() >= _units_to_choose:
		GameData.current_level += 1
		GameData.max_enemy_units += 1
		GameData.map_difficulty += 1

func _apply_upgrade_to_unit(unit_id: int, upgrade: String):
	for unit in get_tree().get_nodes_in_group("Units"):
		if unit.unit_id == unit_id:
			unit.apply_upgrade(upgrade)

			# Ensure list
			if not GameData.unit_upgrades.has(unit_id) or typeof(GameData.unit_upgrades[unit_id]) != TYPE_ARRAY:
				GameData.unit_upgrades[unit_id] = []

			GameData.unit_upgrades[unit_id].append(upgrade)
			return


func _on_continue_button_pressed() -> void:
	get_tree().change_scene_to_file("res://Scenes/Main.tscn")
