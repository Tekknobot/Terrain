extends Control

# @onready variables for each UI element
@onready var name_label = $VBoxContainer3/HBoxContainer2/Name
@onready var portrait = $VBoxContainer3/HBoxContainer/Portrait
@onready var hp_bar = $VBoxContainer3/HBoxContainer/HPBar
@onready var xp_bar = $VBoxContainer3/HBoxContainer/XPBar

@onready var level_label = $VBoxContainer/Level
@onready var hp_label = $VBoxContainer/HP
@onready var xp_label = $VBoxContainer/XP
@onready var movement_label = $VBoxContainer2/MovementRange
@onready var attack_label = $VBoxContainer2/AttackRange
@onready var damage_label = $VBoxContainer2/Damage

@onready var quote_label = $VBoxContainer3/Quote

var quotes = [
	"My mech is locked, loaded, and lethal.",
	"Engaging enemy forces with calculated precision.",
	"All systems green; the battlefield is ours.",
	"Tactical dominance activated—mech in command.",
	"Precision strikes and armored might—battle begins.",
	"Steel, strategy, and unyielding power.",
	"When numbers matter, my mech never falters.",
	"Strategy in motion: mechs, ready to crush.",
	"Mechanized warfare: logic and power combined.",
	"Battlefield clear—target acquired.",
	"Advance, secure, and conquer—mech leads the charge.",
	"The art of war is coded in my circuits.",
	"Calculations complete; enemy defenses fall.",
	"My mech's gears grind for victory.",
	"Overwhelming force, methodically deployed.",
	"Target locked; strike protocol initiated.",
	"Every move precise, every blow decisive.",
	"Mechanized resolve in the heat of battle.",
	"Unyielding armor meets ruthless strategy.",
	"My mech outmaneuvers and outguns the foe.",
	"Data-driven tactics for a brutal battlefield.",
	"Locking in the kill—my mech is on the hunt.",
	"Battle lines drawn; my mech leads the charge.",
	"Efficiency and power—prime directives online.",
	"Calculated aggression: my mech never hesitates.",
	"Deploy and destroy—waging war with precision.",
	"My mech advances where others dare not.",
	"Steel nerves drive this battle to victory.",
	"Precision in motion—no room for error.",
	"Targeting and eliminating with ruthless efficiency.",
	"Dominating the field with superior tactics.",
	"Every decision a step toward victory.",
	"Locked in and lethal—unstoppable force!",
	"Commanding the battlefield with cold precision.",
	"Decisive strikes fueled by iron resolve.",
	"Strategy in steel—my mech writes the playbook.",
	"Paving the way to victory, one mech move at a time.",
	"Our tactics are our strongest weapon.",
	"Relentless pursuit, pinpoint precision.",
	"Mechanized power fused with tactical genius.",
	"Battle commands executed flawlessly.",
	"My mech makes the decisive move.",
	"Command mode: activated. Enemies, beware.",
	"Strategic supremacy in every servo and circuit.",
	"When battle heats up, my mech stays relentless.",
	"Precision engineering meets battlefield strategy.",
	"Every strike calculated, every victory engineered.",
	"We plan, we fight, we conquer.",
	"Victory is mechanized—tactics win wars.",
	"In the heat of battle, my mech is pure resolve."
]

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

# Global ID to control the typewriter effect
var _current_typing_id = 0

func _ready():
	randomize()
	print("name_label:", name_label)
	print("portrait:", portrait)
	print("hp_bar:", hp_bar)
	print("xp_bar:", xp_bar)
	print("level_label:", level_label)
	print("hp_label:", hp_label)
	print("movement_label:", movement_label)
	print("attack_label:", attack_label)
	print("damage_label:", damage_label)
	print("quote_label:", quote_label)
		
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
		portrait.texture = null

	# Update HP Bar
	hp_bar.max_value = player.max_hp
	hp_bar.value = player.current_hp

	# Update XP Bar
	xp_bar.max_value = player.max_xp
	xp_bar.value = player.current_xp

	# Update Level
	level_label.text = "LEVEL: %d" % player.level

	# Update HP and XP Labels
	hp_label.text = "HP: %d of %d" % [player.current_hp, player.max_hp]
	xp_label.text = "XP: %d of %d" % [player.current_xp, player.max_xp]

	# Update Movement, Attack Range, Damage
	movement_label.text = "MOVE: %d" % player.movement_range
	attack_label.text = "ATK: %d" % player.attack_range
	damage_label.text = "DMG: %d" % player.damage

	# Start a new typewriter effect:
	_current_typing_id += 1
	var current_id = _current_typing_id
	var selected_quote = quotes[randi() % quotes.size()]
	await type_quote(selected_quote, current_id)

# Typewriter effect: gradually display the quote letter-by-letter.
func type_quote(quote: String, id: int) -> void:
	quote_label.text = ""
	for i in range(quote.length()):
		# If a new typewriter effect has started, break out.
		if _current_typing_id != id:
			return
		quote_label.text += quote[i]
		await get_tree().create_timer(0.05).timeout
