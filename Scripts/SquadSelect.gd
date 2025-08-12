extends Control

@export var unit_card_scene: PackedScene
@export var melee_units: Array[PackedScene]
@export var ranged_units: Array[PackedScene]
@export var max_squad_size: int = 3
@export var min_squad_size: int = 3  # NEW

@onready var grid: GridContainer = $VBoxContainer/CardGrid
@onready var selection_label: Label = $VBoxContainer/SelectionLabel
@onready var confirm_button: Button = $ConfirmButton
@onready var info_label: Label = $VBoxContainer/Info
@onready var name_label: Label = $Name   # NEW: label that shows the unit's name on hover

var selected_cards: Array[UnitCard] = []

# --- Headlines for the marquee (expanded) ---
const HEADLINES := [
	"Prototype Mek-07 passes endurance test after 48-hour run",
	"Godzilla sighting off Tokyo Bay; coastal sirens tested successfully",
	"City Council approves new anti-kaiju barrier funding",
	"Weather alert: lightning storms power up solar mechs downtown",
	"Random crime spree foiled by patrol unit Aegis-2",
	"R&D leaks: experimental railgun achieves record muzzle velocity",
	"Evac drill scores improve across six districts",
	"Civil defense drones map safe corridors in real time",
	"Factory recall: faulty gyro in Series-3 walkers",
	"Urban heatwave slows non-cooled units by 12%",
	"Test range closed after plasma vent incident -- no injuries reported",
	"Harbor cranes converted to emergency mech gantries",
	"Rogue AI disables dock winches before being sandboxed",
	"Blackout avoided as fusion plant spins up reserve coils",
	"Comms outage traced to kaiju-scale EMP residue",
	"Meteorology: supercell could mask kaiju approach path",
	"Mek pilot graduation rate hits 94% after new sim patch",
	"Insurance rates drop in districts with patrol beacons",
	"Microquakes near tunnel network under Old Town",
	"Public beta: citywide kaiju alert app adds shelter routing",
	"Port authority unveils amphibious heavy lifter ‘Pelican’",
	"Skunkworks denies rumors of stealth-chassis Wisp",
	"Weather drones recover missing cargo pod over bay",
	"Neighborhood watch deploys noise decoys to deter vandals",
	"Trial run: autonomous med-mech completes triage in 3 min"
]

@onready var marquee: RichTextLabel = $Marquee

@export var marquee_speed_cps: float = 8.0  # characters per second

var _marquee_text := ""
var _marquee_offset := 0
var _marquee_accum := 0.0

var _rng := RandomNumberGenerator.new()  # NEW
var _marquee_timer: Timer                # NEW


func _ready() -> void:
	_populate(melee_units)
	_populate(ranged_units)
	_update_ui()
	if not confirm_button.pressed.is_connected(_on_ConfirmButton_pressed):
		confirm_button.pressed.connect(_on_ConfirmButton_pressed)
	if info_label:
		info_label.text = ""
	if name_label:
		name_label.text = ""  # start empty

	# --- Marquee setup ---
	_rng.randomize()

	if marquee:
		marquee.bbcode_enabled = false
		marquee.autowrap_mode = TextServer.AUTOWRAP_OFF
		marquee.fit_content = false
		marquee.custom_minimum_size = Vector2(0, 24)

		_refresh_marquee_text()   # NEW: build randomized text once
		set_process(true)

		# Timer to reshuffle/rebuild every ~12–24s (randomized each cycle)
		_marquee_timer = Timer.new()
		_marquee_timer.one_shot = false
		_marquee_timer.wait_time = _rng.randf_range(60.0, 90.0)
		add_child(_marquee_timer)
		_marquee_timer.timeout.connect(_on_marquee_timeout)
		_marquee_timer.start()

func _randomized_headlines_sequence() -> Array:
	# Start with a shuffled copy
	var seq := HEADLINES.duplicate()
	seq.shuffle()

	# Randomly duplicate a few entries to simulate “trending” items
	var extra_count := _rng.randi_range(2, 5)
	for i in extra_count:
		var pick = HEADLINES[_rng.randi_range(0, HEADLINES.size() - 1)]
		var insert_at := _rng.randi_range(0, seq.size())
		seq.insert(insert_at, pick)

	# Optionally trim to a max length so it doesn’t get gigantic
	var max_len := 24
	if seq.size() > max_len:
		seq = seq.slice(0, max_len)

	return seq


func _refresh_marquee_text() -> void:
	if not marquee:
		return
	var sep := "   -   "
	var seq := _randomized_headlines_sequence()
	var base := sep.join(seq)
	# Duplicate so we can “wrap” seamlessly when slicing
	_marquee_text = base + sep + base
	_marquee_offset = 0
	marquee.text = _marquee_text

func _on_marquee_timeout() -> void:
	_refresh_marquee_text()
	# Randomize next shuffle interval so it feels organic
	_marquee_timer.wait_time = _rng.randf_range(12.0, 24.0)

func _process(delta: float) -> void:
	_update_marquee(delta)

func _update_marquee(delta: float) -> void:
	if not marquee or _marquee_text.is_empty():
		return
	_marquee_accum += delta
	var step_time = 1.0 / max(1.0, marquee_speed_cps)  # time per character shift
	while _marquee_accum >= step_time:
		_marquee_accum -= step_time
		_marquee_offset = (_marquee_offset + 1) % _marquee_text.length()
		var s := _marquee_text.substr(_marquee_offset) + _marquee_text.substr(0, _marquee_offset)
		marquee.text = s

func _populate(list: Array[PackedScene]) -> void:
	for prefab in list:
		var card := unit_card_scene.instantiate() as UnitCard
		grid.add_child(card)
		card.set_from_prefab(prefab)
		card.picked.connect(_on_card_picked)
		card.toggled_selected.connect(_on_card_toggled)
		card.hover_info.connect(_on_card_hover_info)

		# Cache a reliable display name for this card now
		var dn := _derive_unit_name(prefab)
		if dn == "":
			# last-ditch: try the prefab path’s basename
			dn = prefab.resource_path.get_file().get_basename()
		_card_name_cache[card] = dn

func _on_card_hover_info(card: UnitCard, text: String, show: bool) -> void:
	# Put the UNIT NAME in $Name, and keep the detailed hover text in Info (if you want).
	if name_label:
		name_label.text = _get_card_name(card) if show else ""
	if info_label:
		info_label.text = text if show else ""

func _get_card_name(card: UnitCard) -> String:
	# Prefer the cached name we computed from the PackedScene
	if card in _card_name_cache:
		return _card_name_cache[card]

	# Fallbacks (in case a card was created elsewhere)
	if card and card.has_method("get_display_name"):
		return String(card.get_display_name())
	if "display_name" in card:
		return String(card.display_name)
	if "unit_name" in card:
		return String(card.unit_name)
	if "title" in card:
		return String(card.title)
	if card and "unit_prefab" in card and card.unit_prefab:
		return card.unit_prefab.resource_name
	return card.name


func _on_card_picked(card: UnitCard) -> void:
	return

func _on_card_toggled(card: UnitCard, is_selected: bool) -> void:
	if is_selected:
		if selected_cards.size() >= max_squad_size:
			card.set_selected(false, true)
			return
		selected_cards.append(card)
	else:
		selected_cards.erase(card)
	_update_ui()

func _update_ui() -> void:
	selection_label.text = "Selected: %d / %d" % [selected_cards.size(), max_squad_size]
	# Disable if squad is too small OR empty
	confirm_button.disabled = selected_cards.size() < min_squad_size

func _on_ConfirmButton_pressed() -> void:
	# Prevent starting if squad is smaller than min
	if selected_cards.size() < min_squad_size:
		push_warning("You must select at least %d units before proceeding." % min_squad_size)
		return

	var squad_prefabs: Array[PackedScene] = []
	for c in selected_cards:
		squad_prefabs.append(c.unit_prefab)

	GameData.set_selected_squad(squad_prefabs)

	var gd := get_node_or_null("/root/GameData")
	if gd and gd.has_method("set_selected_squad_from_prefabs"):
		gd.set_selected_squad_from_prefabs(squad_prefabs)
	else:
		push_warning("GameData not found or missing set_selected_squad_from_prefabs(). Skipping save.")

	var path := "res://Scenes/OverworldController.tscn"
	var err := get_tree().change_scene_to_file(path)
	if err != OK:
		push_error("Failed to change scene to %s (err=%d)" % [path, err])
	else:
		print("Loading %s..." % path)

var _card_name_cache: Dictionary = {}  # key: UnitCard -> String

func _derive_unit_name(prefab: PackedScene) -> String:
	if prefab == null:
		return ""
	# 1) Try the resource name (filename without extension is often good)
	if prefab.resource_name != "":
		return prefab.resource_name

	# 2) Instance (not added to tree, so no _ready() side effects)
	var inst := prefab.instantiate()
	if inst:
		# Common fields/methods on the unit root
		if inst.has_method("get_display_name"):
			var n = String(inst.get_display_name())
			inst.queue_free()
			return n
		if "display_name" in inst:
			var n = String(inst.display_name)
			inst.queue_free()
			return n
		if "unit_name" in inst:
			var n = String(inst.unit_name)
			inst.queue_free()
			return n
		if "title" in inst:
			var n = String(inst.title)
			inst.queue_free()
			return n

		# Fallback: node name of the root of the unit scene
		var n = inst.name
		inst.queue_free()
		return String(n)

	return ""  # ultimate fallback
