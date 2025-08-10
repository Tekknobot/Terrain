extends Control

@export var unit_card_scene: PackedScene
@export var melee_units: Array[PackedScene]
@export var ranged_units: Array[PackedScene]
@export var max_squad_size: int = 3

@onready var grid: GridContainer = $VBoxContainer/CardGrid
@onready var selection_label: Label = $VBoxContainer/SelectionLabel
@onready var confirm_button: Button = $VBoxContainer/ConfirmButton

var selected_cards: Array[UnitCard] = []

func _ready() -> void:
	_populate(melee_units)
	_populate(ranged_units)
	_update_ui()
	# Ensure the button is actually connected
	if not confirm_button.pressed.is_connected(_on_ConfirmButton_pressed):
		confirm_button.pressed.connect(_on_ConfirmButton_pressed)


func _populate(list: Array[PackedScene]) -> void:
	for prefab in list:
		var card := unit_card_scene.instantiate() as UnitCard
		grid.add_child(card)
		card.set_from_prefab(prefab)
		card.picked.connect(_on_card_picked)
		card.toggled_selected.connect(_on_card_toggled)

func _on_card_picked(card: UnitCard) -> void:
	return

func _on_card_toggled(card: UnitCard, is_selected: bool) -> void:
	if is_selected:
		if selected_cards.size() >= max_squad_size:
			# revert silently (don’t emit again)
			card.set_selected(false, true)
			return
		selected_cards.append(card)
	else:
		selected_cards.erase(card)
	_update_ui()

func _update_ui() -> void:
	selection_label.text = "Selected: %d / %d" % [selected_cards.size(), max_squad_size]
	confirm_button.disabled = selected_cards.size() == 0
	
func _on_ConfirmButton_pressed() -> void:
	var squad_prefabs: Array[PackedScene] = []
	for c in selected_cards:
		squad_prefabs.append(c.unit_prefab)

	GameData.set_selected_squad(squad_prefabs)
	
	# Try to stash the picks in GameData if it exists
	var gd := get_node_or_null("/root/GameData")
	if gd and gd.has_method("set_selected_squad_from_prefabs"):
		gd.set_selected_squad_from_prefabs(squad_prefabs)
	else:
		push_warning("GameData not found or missing set_selected_squad_from_prefabs(). Skipping save.")

	# Change scene (with error logging)
	var path := "res://Scenes/OverworldController.tscn"
	var err := get_tree().change_scene_to_file(path)
	if err != OK:
		push_error("Failed to change scene to %s (err=%d)" % [path, err])
	else:
		print("Loading %s..." % path)
