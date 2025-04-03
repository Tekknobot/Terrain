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
	"Yippity-ki-yay, XP, baby!",
	"I live for these pixelated moments!",
	"Time to kick some digital butt!",
	"May the pixel force be with you!",
	"Keep calm and level up!",
	"Action speaks louder than code!",
	"This upgrade is about to drop like a hot pixel!",
	"Prepare for high scores and low HP!",
	"Lights, camera, action – let's roll!",
	"Victory is just one button press away!",
	"Game on—let's crunch some pixels!",
	"Reloaded and ready to rock the grid!",
	"New level, new legends!",
	"Upgrading like a boss!",
	"I don't code; I conquer!",
	"Watch me debug this level!",
	"Pixels unite—let's roll out!",
	"Game face: ON!",
	"Leveling up, one byte at a time!",
	"Reboot, respawn, rage on!",
	"I press buttons and take names!",
	"Digital hero, activated!",
	"Time to power up and show up!",
	"My code is my superpower!",
	"Strap in, it's game time!",
	"Victory awaits—just a keystroke away!",
	"Loading epic mode…",
	"Onward to digital domination!",
	"Debugging my way to glory!",
	"I don't just play; I slay!",
	"Taking pixel perfection to the next level!",
	"The battlefield is in my code!",
	"I'm the hero of my own script!",
	"Unlocking achievements like a boss!",
	"Command mode: Engage!",
	"Embrace the chaos, level up!",
	"My journey: powered by pixels!",
	"Deploying digital mayhem!",
	"In code we trust, in pixels we conquer!",
	"Ready, set, execute!",
	"Punching pixels with precision!",
	"Charge up! The game awaits!",
	"Rewriting the rules of engagement!",
	"My XP: skyrocketing!",
	"Fear no bug, level up!",
	"Pixels over problems!",
	"Data-driven and determined!",
	"This is my epic upgrade moment!",
	"Victory through variable power!",
	"Powered by code, driven by passion!"
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
