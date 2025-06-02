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
