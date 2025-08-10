# File: res://Scenes/RewardUpgrade.gd
extends CanvasLayer

@export var upgrade_options := [
	"hp_boost",
	"damage_boost",
	"range_boost",
	"move_boost",
]

@export var label_font: Font   # Custom font for labels
@export var button_font: Font  # Custom font for buttons
@export var panel_offset: Vector2 = Vector2.ZERO  # Manual offset from screen center

var chosen_upgrades: Dictionary = {}  # unit_id: selected_upgrade
var _units_to_choose: int = 0

func _ready():
	_center_panel_with_offset()
	# Prevent any clicks on this CanvasLayer from propagating to the TileMap:
	$Control.mouse_filter = Control.MOUSE_FILTER_STOP
	$Control/PanelContainer.mouse_filter = Control.MOUSE_FILTER_STOP

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
	
	GameData.in_upgrade_phase = true
	
	# ─── LOCK MAP INPUT WHILE UI IS OPEN ─────────────────────────────────
	var tilemap = get_tree().get_current_scene().get_node("TileMap")
	#tilemap.input_locked = true
	# ─────────────────────────────────────────────────────────────────────
		
	panel.visible = true
	# Populate fresh choices
	_display_unit_choices()

func _display_unit_choices():
	var units = get_tree().get_nodes_in_group("Units").filter(func(u):
		return u.is_player and is_instance_valid(u)
	)
	_units_to_choose = units.size()

	# Container where each unit's options vbox will go
	var upgrade_container = $Control/PanelContainer/MarginContainer/VBoxContainer/UpgradeContainer

	# Clear any old choices
	for child in upgrade_container.get_children():
		upgrade_container.remove_child(child)

	# Create a VBox for each unit
	for unit in units:
		var unit_id = unit.unit_id
		var vbox = VBoxContainer.new()
		vbox.name = str(unit_id)
		
		# Portrait (kept aspect ratio)
		if unit.portrait:
			var portrait = TextureRect.new()
			portrait.texture      = unit.portrait
			portrait.size         = Vector2(32, 32)
			portrait.expand_mode  = TextureRect.EXPAND_FIT_HEIGHT_PROPORTIONAL
			portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			vbox.add_child(portrait)

			if unit.mek_portrait:
				var mek = TextureRect.new()
				mek.texture      = unit.mek_portrait
				mek.size         = Vector2(32, 32)
				mek.expand_mode  = TextureRect.EXPAND_FIT_HEIGHT_PROPORTIONAL
				mek.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				vbox.add_child(mek)
		
		# Prepare and shuffle options
		var options = upgrade_options.duplicate()
		if unit.unit_type == "Melee":
			options.erase("range_boost")
		options.shuffle()

		# Create one button per option
		for i in range(3):
			var upgrade = options[i]
			var btn = Button.new()
			# Remove 'boost' suffix and capitalize for display
			var label_text = upgrade.replace("_boost", "").capitalize()
			btn.text = label_text

			# Apply inspector-chosen font and size override
			if button_font:
				btn.add_theme_font_override("font", button_font)
				btn.add_theme_font_size_override("font_size", 32)
			
			# Ensure a minimum size so UI doesn’t shrink/grow
			btn.custom_minimum_size = Vector2(72, 16)

			# Signal
			btn.pressed.connect(Callable(self, "_on_upgrade_chosen").bind(unit_id, upgrade))
			vbox.add_child(btn)

		# Add to main container
		upgrade_container.add_child(vbox)
		
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

	# If last unit chosen, auto-advance
	if chosen_upgrades.size() >= _units_to_choose:
		_on_continue_button_pressed()

func _apply_upgrade_to_unit(unit_id: int, upgrade: String) -> void:
	for unit in get_tree().get_nodes_in_group("Units"):
		if unit.unit_id == unit_id:
			unit.apply_upgrade(upgrade)
			if not GameData.unit_upgrades.has(unit_id) or typeof(GameData.unit_upgrades[unit_id]) != TYPE_ARRAY:
				GameData.unit_upgrades[unit_id] = []
			GameData.unit_upgrades[unit_id].append(upgrade)
			break

func _on_continue_button_pressed() -> void:
	GameData.in_upgrade_phase = false
	var tilemap = get_tree().get_current_scene().get_node("TileMap")
	tilemap.input_locked = false

	# ✅ BUILD CARRYOVER SNAPSHOT (units to re-spawn next map with upgrades)
	GameData.carryover_units.clear()
	for unit in get_tree().get_nodes_in_group("Units"):
		if not is_instance_valid(unit): 
			continue
		if not unit.is_player: 
			continue
		if unit.health <= 0: 
			continue  # skip dead ones

		# scene path is needed to re-instantiate the same scene next map
		var scene_path := ""
		if unit.has_meta("scene_path"):
			scene_path = String(unit.get_meta("scene_path"))

		if scene_path == "":
			continue  # avoid bad loads next map

		# pull upgrades by value and copy (ids will change next map)
		var upgs: Array = GameData.get_upgrades(unit.unit_id)
		var special_name := GameData.get_unit_special(unit.unit_id)

		GameData.carryover_units.append({
			"scene_path": scene_path,
			"max_health": unit.max_health,
			"health":     unit.health,
			"upgrades":   upgs.duplicate(true),
			"special":    special_name,
			"level":      unit.level,   # keep current level so we can +1 next map
		})

	# (your existing progression)
	GameData.mark_map_completed(GameData.current_level)
	GameData.current_level += 1
	GameData.max_enemy_units += 1
	GameData.map_difficulty += 1

	get_tree().change_scene_to_file("res://Scenes/OverworldController.tscn")
