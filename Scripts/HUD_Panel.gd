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

# Array of quotes (playful, action-inspired)
var quotes = [
	"Revving up my mech—time to strategize and dominate!",
	"Engage hyper-mode: tactical precision and steel resolve!",
	"Decisions made: this mech's got your back!",
	"In the future, my mech speaks louder than words!",
	"Lock, load, and let the mech roll out!",
	"Battle plans set: unleash the mechanical might!",
	"My mech’s heart beats to the rhythm of strategy!",
	"Tactical brilliance meets raw mech power—let's roll!",
	"When decisions are tough, trust in your mech!",
	"Deploying my mech for the ultimate showdown!",
	"Future battles demand precision and mega mechs!",
	"Every decision fuels my mech’s firepower!",
	"Strap in—mech mode activated for epic combat!",
	"The future is forged in steel and sharp tactics!",
	"Calculated risk: deploy the mech and conquer!",
	"My mech is a fortress, and strategy is its core!",
	"Precision, power, and a dash of mecha magic!",
	"Not just a machine—it's a tactical powerhouse!",
	"Outthinking the enemy, one mech move at a time!",
	"The battlefield is chess; my mech is the queen!",
	"Planning and power: mechs do it with style!",
	"Onward to victory—my mech leads the charge!",
	"Reboot, recalibrate, then crush with mech might!",
	"When the future calls, my mech answers with force!",
	"Decision time: engage the mech and reshape fate!",
	"Battle strategy activated: let the mechs roll!",
	"My mech and I: the ultimate dream team!",
	"Calculating victory, one strategic move at a time!",
	"Powered by steel and tactical genius!",
	"Every battle starts with a smart decision!",
	"Engage mech mode: where strategy meets brawn!",
	"The art of war: sharp tactics and thunderous mechs!",
	"Built on steel, strategy, and unstoppable mechs!",
	"Strategy is the mind; my mech is the muscle!",
	"In tomorrow’s arena, my mech writes the playbook!",
	"Let the enemy tremble before our tactics!",
	"Onward to glory—my mech and I are synced!",
	"It's not just power—it’s the perfect decision!",
	"My mech’s systems are tuned for epic strategy!",
	"Deploying tactical firepower—mech on the move!",
	"Every epic battle begins with a key decision!",
	"In the mech era, strategy is king and power its knight!",
	"Time to turn tactics into triumph with a mech strike!",
	"Calculated chaos: let the battle begin!",
	"When it matters most, trust a well-oiled mech!",
	"Brains and brawn combined—my mech is unstoppable!",
	"Precision and power: every mech move counts!",
	"Battlefield decisions made from my cockpit!",
	"In the future, every decision is a game-changer!"
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

	# Update Quote: choose one randomly, double it, then type it out like a typewriter.
	var selected_quote = quotes[randi() % quotes.size()]
	# Use await to run the typewriter effect (ensure update_hud is called in an async context)
	await type_quote(selected_quote)

# Typewriter effect: gradually display the quote letter-by-letter.
func type_quote(quote: String) -> void:
	quote_label.text = ""
	# Loop over each character and append it with a delay.
	for i in range(quote.length()):
		quote_label.text += quote[i]
		await get_tree().create_timer(0.05).timeout
