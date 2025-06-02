# HUD.gd (extends Control)
extends Control

# @onready variables for each UI element
@onready var name_label    = $VBoxContainer3/HBoxContainer2/Name
@onready var portrait      = $VBoxContainer3/HBoxContainer/Portrait
@onready var hp_bar        = $VBoxContainer3/HBoxContainer/HPBar
@onready var xp_bar        = $VBoxContainer3/HBoxContainer/XPBar

@onready var level_label   = $VBoxContainer/Level
@onready var hp_label      = $VBoxContainer/HP
@onready var xp_label      = $VBoxContainer/XP
@onready var movement_label= $VBoxContainer2/MovementRange
@onready var attack_label  = $VBoxContainer2/AttackRange
@onready var damage_label  = $VBoxContainer2/Damage

@onready var quote_label   = $VBoxContainer3/Quote

@onready var ability_button = $Ability

var quotes = [
	"My mech is charged and ready to bring the thunder.",
	"When my Gundam stands tall the battlefield trembles.",
	"Punching kaiju in the face is just another Tuesday.",
	"Deploying beam saber for maximal style points.",
	"Sync ratio at one hundred percent let’s do this.",
	"Armor full throttle engage transformation protocol.",
	"Rocket punch incoming prepare for impact.",
	"Locking onto target with my Jaeger radar.",
	"All systems nominal ready to beat the thing out of those kaiju.",
	"Piloting my EVA suit like it’s my second skin.",
	"Stand by to defy gravity with overclocked boosters.",
	"Brace for impact as my mecha delivers the final blow.",
	"Target acquired initiating laser cannon sequence.",
	"Can’t stop won't stop until every kaiju hits the floor.",
	"Transformation complete now my mech moves like liquid steel.",
	"Engaging plasma blade to slice through that rogue AI.",
	"Synchronizing neural link for ultimate control.",
	"Override engaged when my mech goes berserk.",
	"Unleashing missile barrage with reckless abandon.",
	"Charging fusion core this is going to be epic.",
	"Up your anime references I pilot with style.",
	"Fearless in my Gundam ready to rewrite history.",
	"Giant robot on standby ready for foil behemoths.",
	"Calibrating servos let’s show them what precision feels like.",
	"Target locked calibrating railgun for orbital strike.",
	"Synapse link active I feel the mech in my bones.",
	"Wings deployed ready to dogfight those rogue drones.",
	"Time to throw down metal fists of justice.",
	"Initiating overdrive where no robot has gone before.",
	"Stand tall like a sentient titan when the world needs you.",
	"Deploy energy shield to deflect incoming capacitance.",
	"Activate stealth mode now you see us now you don’t.",
	"Operating on pure adrenaline and propellent fuel.",
	"Nothing stands between my frame and battlefield glory.",
	"Synching coordinates for devastating meteor strike.",
	"Deploying tactical drones to confuse that mech swarm.",
	"Lock and load with quad barrels ready to rock.",
	"Piloting this beast like an interstellar cowboy.",
	"Arm cannon ready prime the disruptor beams.",
	"Pulse drive engaged let’s outrun those giant bots.",
	"Synchronize cores watch us light up the night sky.",
	"Ready to unleash the ultimate combination attack.",
	"System check complete we are unstoppable.",
	"Engineering marvel meets combat prowess let’s roll.",
	"Override caution protocol maximum aggression mode.",
	"Propulsion thrusters blazing time to dominate.",
	"Opening reactor vent to supercharge the main gun.",
	"My mecha’s roar echoes across the stars.",
	"Final form activated we bring the apocalypse.",
	"Stand clear this is going to get mecha sized.",
	"Upgrade complete let’s show those bots who’s boss.",
	"Operational synergy achieved we fight as one."
]


# Example player data structure (used on initial spawn, etc.)
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

	# 1) When all units have spawned, update HUD with some default (e.g. player_data).
	#    Only the server should connect to "units_spawned" so it can broadcast to clients.
	if is_multiplayer_authority():
		var game = get_node("/root/BattleGrid")
		game.connect("units_spawned", Callable(self, "_on_units_spawned"))

	# 2) ALSO connect to the TileMap’s `unit_selected(Unit)` signal on every peer:
	var tilemap = get_node("/root/BattleGrid/TileMap")
	tilemap.connect("unit_selected", Callable(self, "_on_unit_selected"))

func _on_units_spawned():
	# This function runs on the server when units spawn. It updates
	# the server’s HUD immediately, then tells all clients to do the same.
	update_hud(player_data)
	rpc("update_hud", player_data)


@rpc
func update_hud(player):
	# --- Update all HUD fields for the “player” dictionary ---
	name_label.text = player.name

	if player.portrait:
		portrait.texture = player.portrait
	else:
		portrait.texture = null

	hp_bar.max_value = player.max_hp
	hp_bar.value = player.current_hp

	xp_bar.max_value = player.max_xp
	xp_bar.value = player.current_xp

	level_label.text = "LEVEL: %d" % player.level
	hp_label.text    = "HP: %d of %d" % [player.current_hp, player.max_hp]
	xp_label.text    = "XP: %d of %d" % [player.current_xp, player.max_xp]

	movement_label.text = "MOVE: %d" % player.movement_range
	attack_label.text   = "ATK: %d" % player.attack_range
	damage_label.text   = "DMG: %d" % player.damage

	# Hide the ability button by default (we’ll show it when a unit is selected)
	ability_button.visible = false

	# Start a fresh typewriter‐style quote
	_current_typing_id += 1
	var current_id = _current_typing_id
	var selected_quote = quotes[randi() % quotes.size()]
	await type_quote(selected_quote, current_id)

func type_quote(quote: String, id: int) -> void:
	quote_label.text = ""
	for i in range(quote.length()):
		if _current_typing_id != id:
			return
		quote_label.text += quote[i]
		await get_tree().create_timer(0.05).timeout

func _on_unit_selected(unit):
	var id = unit.unit_id
	print("[HUD] Selected unit ‘%s’ (id=%d)  is_player=%s" % [unit.unit_name, id, unit.is_player])

	# 1) Always hide the button to start
	ability_button.visible = false

	# 2) If it’s not a player‐team unit, bail immediately
	if not unit.is_player:
		#return
		pass

	# 3) If it does have an entry in GameData.unit_upgrades _and_ that entry is non‐empty,
	#    show it. Otherwise leave it hidden.
	if GameData.unit_upgrades.has(id):
		var ability = GameData.unit_upgrades[id]
		if ability != "":
			ability_button.text = ability
			ability_button.visible = true


func _on_ability_toggled(toggled_on: bool) -> void:
	# Immediately ask the server to turn this ability on/off,
	# regardless of whether I am host or client.
	if toggled_on:
		var chosen_text = ability_button.text
		# Always send to peer 1 (the host).
		rpc_id(1, "server_handle_ability_toggle_on", chosen_text)
	else:
		rpc_id(1, "server_handle_ability_toggle_off")


# ----------------------------------------------------
# SERVER‐ONLY RPCs: The server receives these and then
# broadcasts the result via `sync_ability_mode`.
# ----------------------------------------------------
@rpc
func server_handle_ability_toggle_on(chosen_ability: String) -> void:
	_set_mode_on_server(chosen_ability)
	rpc("sync_ability_mode", chosen_ability)

@rpc
func server_handle_ability_toggle_off() -> void:
	_clear_modes_on_server()
	rpc("sync_ability_mode", "")


func _set_mode_on_server(mode_name: String) -> void:
	var tilemap = get_node("/root/BattleGrid/TileMap")
	# Clear everything first:
	_clear_all_modes(tilemap)

	# Then enable only the requested mode:
	match mode_name:
		"Critical Strike":
			tilemap.critical_strike_mode = true
		"Rapid Fire":
			tilemap.rapid_fire_mode = true
		"Healing Wave":
			tilemap.healing_wave_mode = true
		"Overcharge":
			tilemap.overcharge_attack_mode = true
		"Explosive Rounds":
			tilemap.explosive_rounds_mode = true
		"Spider Blast":
			tilemap.spider_blast_mode = true
		"Thread Attack":
			tilemap.thread_attack_mode = true
		"Lightning Surge":
			tilemap.lightning_surge_mode = true
		_:
			# If something unexpected arrives, just clear everything
			_clear_all_modes(tilemap)

func _clear_modes_on_server() -> void:
	var tilemap = get_node("/root/BattleGrid/TileMap")
	_clear_all_modes(tilemap)

func _clear_all_modes(tilemap: Node) -> void:
	tilemap.critical_strike_mode    = false
	tilemap.rapid_fire_mode         = false
	tilemap.healing_wave_mode       = false
	tilemap.overcharge_attack_mode  = false
	tilemap.explosive_rounds_mode   = false
	tilemap.spider_blast_mode       = false
	tilemap.thread_attack_mode      = false
	tilemap.lightning_surge_mode    = false

# ----------------------------------------------------
# CLIENT + SERVER: When the server broadcasts “sync_ability_mode”,
# each peer applies the same change locally.
# ----------------------------------------------------
@rpc
func sync_ability_mode(mode_name: String) -> void:
	var tilemap = get_node("/root/BattleGrid/TileMap")
	_clear_all_modes(tilemap)

	if mode_name == "":
		return  # Nothing to enable

	match mode_name:
		"Critical Strike":
			tilemap.critical_strike_mode = true
		"Rapid Fire":
			tilemap.rapid_fire_mode = true
		"Healing Wave":
			tilemap.healing_wave_mode = true
		"Overcharge":
			tilemap.overcharge_attack_mode = true
		"Explosive Rounds":
			tilemap.explosive_rounds_mode = true
		"Spider Blast":
			tilemap.spider_blast_mode = true
		"Thread Attack":
			tilemap.thread_attack_mode = true
		"Lightning Surge":
			tilemap.lightning_surge_mode = true
		_:
			# If something unexpected arrives, keep all false
			pass

	tilemap._clear_highlights()
