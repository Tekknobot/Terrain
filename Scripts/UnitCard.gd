# res://Scripts/UnitCard.gd
extends TextureButton
class_name UnitCard

signal picked(card: UnitCard)
signal toggled_selected(card: UnitCard, is_selected: bool)
signal hover_info(card: UnitCard, text: String, show: bool)  # NEW

@export var card_min_size: Vector2 = Vector2(200, 200)

var unit_prefab: PackedScene
var is_selected := false
var is_hovered := false  # NEW

# optional: an overlay TextureRect for the Mek image (created if missing)
var mek_rect: TextureRect

# Hover visuals (tweak to taste)
@export var hover_scale := 1.05
@export var hover_border_width := 4
@export var hover_border_color := Color(1, 1, 1, 0.9)
@export var hover_border_corner_radius := 12

# Selected visuals still use your existing grey modulate;
# you can change that here if you want.
@export var selected_modulate := Color(0.1, 0.1, 0.1)
@export var normal_modulate := Color(1, 1, 1)

# At top with other exports/vars
@export var overlay_offset: Vector2 = Vector2(32, -24)   # right & up
@export_range(0.2, 1.2, 0.01) var overlay_scale: float = 0.9

# NEW: cached hover outline node
var hover_outline: Panel

# --- NEW: wiggle settings ---
@export var wiggle_amp_degrees := 3.0   # how far it tilts left/right
@export var wiggle_speed_hz := 3.0      # wiggles per second

var _hover_t := 0.0                      # time accumulator for wiggle

var info_text: String = ""                                   # NEW

const ABILITIES := {
	"Ground Slam": "shockwave hits all adjacent tiles even if empty",
	"Mark and Pounce": "lock target leap in and strike with damage",
	"High Arching Shot": "lands in 3x3 zone strong damage in center",
	"Suppressive Fire": "fire at all within range",
	"Guardian Halo": "give ally one round shield lost if missed",
	"Fortify": "halve all damage taken until next turn and fire laser arcs within range",
	"Heavy Rain": "missile barrage over wide area damage with passive healing",
	"Web Field": "zone in and damage all enemies 3x3 with passive healing"
}

func _layout_overlay(pilot_tx: Texture2D, mek_tx: Texture2D) -> void:
	mek_rect.set_anchors_preset(Control.PRESET_TOP_LEFT)
	mek_rect.stretch_mode = TextureRect.STRETCH_SCALE
	mek_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	var base_size := pilot_tx.get_size()
	var size := base_size * overlay_scale
	mek_rect.size = size
	mek_rect.position = overlay_offset

func _ready() -> void:
	custom_minimum_size = card_min_size
	stretch_mode = TextureButton.STRETCH_SCALE
	focus_mode = Control.FOCUS_NONE

	# NEW: pivot at center so rotation looks natural
	_update_pivot()
	if not resized.is_connected(_on_resized):
		resized.connect(_on_resized)

	# build a child overlay to draw the mek portrait on top (if provided)
	mek_rect = get_node_or_null("Mek") as TextureRect
	if mek_rect == null:
		mek_rect = TextureRect.new()
		mek_rect.name = "Mek"
		mek_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		mek_rect.stretch_mode = TextureRect.STRETCH_SCALE
		mek_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mek_rect.visible = false
		add_child(mek_rect)
		mek_rect.set_anchors_preset(Control.PRESET_FULL_RECT)

	# NEW: make a hover outline panel that only shows on hover
	hover_outline = get_node_or_null("HoverOutline") as Panel
	if hover_outline == null:
		hover_outline = Panel.new()
		hover_outline.name = "HoverOutline"
		hover_outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(hover_outline)
		hover_outline.set_anchors_preset(Control.PRESET_FULL_RECT)
		hover_outline.z_index = -1  # keep above card image

		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0, 0, 0, 0) # transparent fill
		sb.border_width_left = hover_border_width
		sb.border_width_top = hover_border_width
		sb.border_width_right = hover_border_width
		sb.border_width_bottom = hover_border_width
		sb.border_color = hover_border_color
		sb.corner_radius_top_left = hover_border_corner_radius
		sb.corner_radius_top_right = hover_border_corner_radius
		sb.corner_radius_bottom_left = hover_border_corner_radius
		sb.corner_radius_bottom_right = hover_border_corner_radius
		hover_outline.add_theme_stylebox_override("panel", sb)
		hover_outline.visible = false

	# NEW: connect hover signals
	if not mouse_entered.is_connected(_on_mouse_entered):
		mouse_entered.connect(_on_mouse_entered)
	if not mouse_exited.is_connected(_on_mouse_exited):
		mouse_exited.connect(_on_mouse_exited)

	_apply_visuals()

# NEW: keep pivot centered if the control resizes
func _on_resized() -> void:
	_update_pivot()

func _update_pivot() -> void:
	# Control uses pivot_offset for rotation/scale center
	pivot_offset = size * 0.5

func set_from_prefab(prefab: PackedScene) -> void:
	unit_prefab = prefab
	var ghost := prefab.instantiate() as Area2D

	var u_name: String         = ghost.unit_name
	var u_type: String         = ghost.unit_type
	var pilot_tx: Texture2D    = ghost.portrait as Texture2D
	var mek_tx: Texture2D      = ghost.get_mek_portrait() as Texture2D
	var hp: int                = int(ghost.health)
	var hp_max: int            = int(ghost.max_health)
	var atk: int               = int(ghost.damage)
	var rng: int               = int(ghost.attack_range)
	var mov: int               = int(ghost.movement_range)
	var defv: int              = int(ghost.defense)
	var special: String        = str(ghost.default_special)
	ghost.queue_free()

	# button visuals
	texture_normal = pilot_tx
	texture_hover = pilot_tx   # keep same art; hover is handled by border/scale
	texture_pressed = pilot_tx

	# show mek overlay if present
	if mek_tx:
		mek_rect.texture = mek_tx
		_layout_overlay(pilot_tx, mek_tx)
		mek_rect.visible = true
	else:
		if mek_rect:
			mek_rect.visible = false

	# Decide melee/ranged label as you already do
	var combat_class := "Ranged" if rng > 1 else "Melee"

	# DEF only when non-zero (as you had)
	var def_part := "  DEF %d" % defv if defv != 0 else ""

	# Ability name + description (normalized lookup; falls back to name)
	var spec_part := ""
	if special != "":
		var desc := _ability_desc(special)
		if desc != "":
			spec_part = "\n%s: %s" % [special, desc]   # added line break here
		else:
			spec_part = "\n%s" % special               # and here

	# Final text used for the HOVER INFO (emitted in _on_mouse_entered)
	info_text = "%s - %s [%s]\nHP %d/%d  DMG %d  ATK %d  MOV %d%s%s" % [
		u_name, u_type, combat_class, hp, hp_max, atk, rng, mov, def_part, spec_part
	]

func _pressed() -> void:
	emit_signal("picked", self)
	set_selected(!is_selected)

func set_selected(selected: bool, silent: bool=false) -> void:
	is_selected = selected
	_apply_visuals()
	if not silent:
		emit_signal("toggled_selected", self, is_selected)

# NEW: hover handlers
func _on_mouse_entered() -> void:
	is_hovered = true
	_hover_t = 0.0
	emit_signal("hover_info", self, info_text, true)   # NEW
	_apply_visuals()

func _on_mouse_exited() -> void:
	is_hovered = false
	_hover_t = 0.0
	rotation_degrees = 0.0
	emit_signal("hover_info", self, "", false)         # NEW
	_apply_visuals()


# NEW: per-frame wiggle (rotation only – container-safe)
func _process(delta: float) -> void:
	if is_hovered:
		_hover_t += delta
		# sine wave in degrees
		rotation_degrees = sin(_hover_t * TAU * wiggle_speed_hz) * wiggle_amp_degrees
	else:
		# ensure we stay perfectly upright when not hovering
		if abs(rotation_degrees) > 0.001:
			rotation_degrees = 0.0

# NEW: single place to update visuals
func _apply_visuals() -> void:
	# Selection tint
	modulate = selected_modulate if is_selected else normal_modulate

	# Outline visibility / color as you like
	if hover_outline:
		hover_outline.visible = is_hovered
		# (optional) if you want color swap instead:
		# var col := is_selected ? Color(1.0,0.85,0.2,1.0)
		#     : (is_hovered ? hover_border_color : Color(1,1,1,0))
		# (hover_outline.get_theme_stylebox("panel") as StyleBoxFlat).border_color = col

	# Subtle scale on hover
	var target_scale := hover_scale if is_hovered else 1.0
	scale = Vector2(target_scale, target_scale)

# --- add anywhere in UnitCard.gd (top-level) ---

func _normalize_ability_key(s: String) -> String:
	var t := s.strip_edges().to_lower()
	t = t.replace("&", "and")
	# collapse multiple spaces
	while t.find("  ") != -1:
		t = t.replace("  ", " ")
	return t

func _ability_desc(name: String) -> String:
	var want := _normalize_ability_key(name)
	for k in ABILITIES.keys():
		if _normalize_ability_key(k) == want:
			return ABILITIES[k]
	return ""
