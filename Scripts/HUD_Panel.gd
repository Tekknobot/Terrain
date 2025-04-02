extends Control

# @onready variables for each UI element
@onready var name_label = $VBoxContainer3/Name
@onready var portrait = $VBoxContainer3/HBoxContainer/Portrait
@onready var hp_bar = $VBoxContainer3/HBoxContainer/HPBar
@onready var xp_bar = $VBoxContainer3/HBoxContainer/XPBar

@onready var level_label = $VBoxContainer/Level
@onready var hp_label = $VBoxContainer/HP
@onready var movement_label = $VBoxContainer2/MovementRange
@onready var attack_label = $VBoxContainer2/AttackRange
@onready var damage_label = $VBoxContainer2/Damage

# Example player data structure
var player_data = {
	"name": "Hero",
	"portrait": null,
	"current_hp": 30,
	"max_hp": 50,
	"current_xp": 80,
	"max_xp": 100,
	"level": 2,
	"movement_range": 3,
	"attack_range": 1,
	"damage": 5
}

func _ready():
	print("name_label:", name_label)
	print("portrait:", portrait)
	print("hp_bar:", hp_bar)
	print("xp_bar:", xp_bar)
	print("level_label:", level_label)
	print("hp_label:", hp_label)
	print("movement_label:", movement_label)
	print("attack_label:", attack_label)
	print("damage_label:", damage_label)
		
	var game = get_node("/root/BattleGrid")  # Adjust path accordingly.
	game.connect("units_spawned", Callable(self, "_on_units_spawned"))	
	
func _on_units_spawned():
	update_hud(player_data)
	
func update_hud(player):
	# Update Name
	name_label.text = player.name

	# Update Portrait (assuming `player.portrait` is a Texture)
	if player.portrait:
		portrait.texture = player.portrait
	else:
		# Optionally set a default texture or leave it blank
		portrait.texture = null
	
	# Update HP Bar
	hp_bar.max_value = player.max_hp
	hp_bar.value = player.current_hp

	# Update XP Bar
	xp_bar.max_value = player.max_xp
	xp_bar.value = player.current_xp

	# Update Level
	level_label.text = "LEVEL: %d" % player.level

	# Update HP (RichTextLabel or Label)
	hp_label.text = "HP: %d / %d" % [player.current_hp, player.max_hp]

	# Update Movement, Attack Range, Damage
	movement_label.text = "MOVEMENT: %d" % player.movement_range
	attack_label.text = "ATTACK: %d" % player.attack_range
	damage_label.text = "DAMAGE: %d" % player.damage
