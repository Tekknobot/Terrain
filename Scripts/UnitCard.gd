# res://Scripts/UnitCard.gd
extends TextureButton
class_name UnitCard

signal picked(card: UnitCard)
signal toggled_selected(card: UnitCard, is_selected: bool)

@export var card_min_size: Vector2 = Vector2(200, 200)

var unit_prefab: PackedScene
var is_selected := false

# optional: an overlay TextureRect for the Mek image (created if missing)
var mek_rect: TextureRect

# At top with other exports/vars
@export var overlay_offset: Vector2 = Vector2(32, -24)   # right & up
@export_range(0.2, 1.2, 0.01) var overlay_scale: float = 0.9

func _layout_overlay(pilot_tx: Texture2D, mek_tx: Texture2D) -> void:
	# Anchor to top-left so position works as a pixel offset
	mek_rect.set_anchors_preset(Control.PRESET_TOP_LEFT)
	mek_rect.stretch_mode = TextureRect.STRETCH_SCALE
	mek_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE

	# Base the overlay size on the pilot texture (so it shrinks a bit)
	var base_size := pilot_tx.get_size()
	var size := base_size * overlay_scale
	mek_rect.size = size

	# Diagonal offset (e.g., a little to the right and up)
	mek_rect.position = overlay_offset

func _ready() -> void:
	custom_minimum_size = card_min_size
	stretch_mode = TextureButton.STRETCH_SCALE
	focus_mode = Control.FOCUS_NONE
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

func set_from_prefab(prefab: PackedScene) -> void:
	unit_prefab = prefab
	var ghost := prefab.instantiate() as Area2D

	# pull data from your unit script (typed)
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
	# keep hover/pressed the same unless you want different looks
	texture_hover = pilot_tx
	texture_pressed = pilot_tx
	# show mek overlay if present
	if mek_tx:
		mek_rect.texture = mek_tx
		_layout_overlay(pilot_tx, mek_tx)
		mek_rect.visible = true
	else:
		if mek_rect:
			mek_rect.visible = false

	# helpful tooltip (since there are no labels on the card)
	var combat_class := "Ranged" if rng > 1 else "Melee"
	var def_part := "  DEF %d" % defv if defv != 0 else ""
	var spec_part := " —  %s" % special if special != "" else ""
	tooltip_text = "%s — %s [%s]\nHP %d/%d  ATK %d  RNG %d  MOV %d%s%s" % [
		u_name, u_type, combat_class, hp, hp_max, atk, rng, mov, def_part, spec_part
	]

func _pressed() -> void:
	emit_signal("picked", self)
	set_selected(!is_selected)

func set_selected(selected: bool, silent: bool=false) -> void:
	is_selected = selected
	modulate = Color(0.5, 0.5, 0.5) if is_selected else Color(1, 1, 1)
	if not silent:
		emit_signal("toggled_selected", self, is_selected)
