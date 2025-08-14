extends Control

@export var font_path: String = "res://Fonts/magofonts/mago1.ttf"
@export var heading_font_path: String = "res://Fonts/magofonts/mago3.ttf"
@export var font_size: int = 16
@export var heading_font_size: int = 32

const SETTINGS_PATH := "user://settings.cfg"

var _tutorials := [
	{
		"key": "basics",
		"title": "Basics",
		"desc": "Movement, camera, and basic interaction."
	},
	{
		"key": "combat",
		"title": "Combat",
		"desc": "Attacking, blocking, abilities, and stamina."
	},
	{
		"key": "squad",
		"title": "Squad & Upgrades",
		"desc": "Selecting units, roles, and upgrading gear."
	}
]

# Filled in _ready() (strings, no lambdas to avoid parse issues)
var _tutorial_bbcode := {}

# Runtime nodes (for side-by-side layout)
var _list_box: VBoxContainer
var _readme_title: Label
var _readme_label: RichTextLabel

func _ready() -> void:
	# Build the bbcode dictionary once
	_tutorial_bbcode["basics"] = _bb_controls() + "\n" + _bb_terrain() + "\n" + _bb_push()
	_tutorial_bbcode["combat"] = _bb_specials() + "\n" + _bb_push()
	_tutorial_bbcode["squad"] = (
		"[b]Squad & Upgrades[/b]\n"
		+ "• Select units that complement each other (ranged + brawler + utility).\n"
		+ "• Upgrades improve HP, range, abilities, and mobility.\n"
		+ "• Synergize abilities (e.g., [i]Web Field[/i] to trap, then [i]High-Arcing Shot[/i]).\n\n"
		+ _bb_push()
	)

	_build_ui()

# ---------------- UI BUILD (split view) ----------------
func _build_ui() -> void:
	# Clear (hot reload safety)
	for c in get_children():
		remove_child(c)
		c.queue_free()

	# OUTER MARGINS (matches settings window)
	# === Centered grey card with white border (matches Settings) ===
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(center)

	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	panel.add_theme_stylebox_override("panel", _make_card_style())  # <-- use helper
	center.add_child(panel)

	# inner breathing room
	var card_pad := MarginContainer.new()
	card_pad.add_theme_constant_override("margin_left", 8)
	card_pad.add_theme_constant_override("margin_right", 8)
	card_pad.add_theme_constant_override("margin_top", 8)
	card_pad.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(card_pad)

	# OUTER MARGINS inside the card pad
	var outer := MarginContainer.new()
	outer.add_theme_constant_override("margin_left", 20)
	outer.add_theme_constant_override("margin_right", 20)
	outer.add_theme_constant_override("margin_top", 16)
	outer.add_theme_constant_override("margin_bottom", 16)
	card_pad.add_child(outer)

	# ROOT COLUMN inside margins
	var root := VBoxContainer.new()
	root.custom_minimum_size = Vector2(900, 520)
	root.add_theme_constant_override("separation", 12)
	outer.add_child(root)


	# THEME (fonts)
	var theme := Theme.new()
	if ResourceLoader.exists(font_path):
		var body_font := load(font_path) as FontFile
		if body_font:
			theme.set_default_font(body_font)
			theme.set_default_font_size(font_size)
	root.theme = theme

	var heading_font: FontFile
	if heading_font_path != "" and ResourceLoader.exists(heading_font_path):
		heading_font = load(heading_font_path) as FontFile

	# TITLE
	var title := Label.new()
	title.text = "Tutorials"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_constant_override("margin_left", 8)
	title.add_theme_constant_override("margin_right", 8)
	if heading_font:
		title.add_theme_font_override("font", heading_font)
		title.add_theme_font_size_override("font_size", heading_font_size)
	root.add_child(title)

	root.add_child(HSeparator.new())

	# SPLIT ROW
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(row)

	# -------- LEFT: LIST (scrollable) --------
	var left_pad := MarginContainer.new()
	left_pad.add_theme_constant_override("margin_left", 8)
	left_pad.add_theme_constant_override("margin_right", 8)
	left_pad.add_theme_constant_override("margin_top", 6)
	left_pad.add_theme_constant_override("margin_bottom", 6)
	left_pad.custom_minimum_size = Vector2(420, 0)   # give the list a steady width
	row.add_child(left_pad)

	var left_scroll := ScrollContainer.new()
	left_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_pad.add_child(left_scroll)

	_list_box = VBoxContainer.new()
	_list_box.add_theme_constant_override("separation", 10)
	left_scroll.add_child(_list_box)

	for t in _tutorials:
		var completed := _get_completed(t.key)
		_list_box.add_child(_make_tutorial_row(t.key, t.title, t.desc, completed))

	# -------- RIGHT: README PANEL --------
	var right_pad := MarginContainer.new()
	right_pad.add_theme_constant_override("margin_left", 8)
	right_pad.add_theme_constant_override("margin_right", 8)
	right_pad.add_theme_constant_override("margin_top", 6)
	right_pad.add_theme_constant_override("margin_bottom", 6)
	right_pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_pad.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(right_pad)

	var right_col := VBoxContainer.new()
	right_col.add_theme_constant_override("separation", 8)
	right_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL        # <-- add
	right_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_pad.add_child(right_col)

	# Readme title
	_readme_title = Label.new()
	_readme_title.text = "Select a tutorial"
	_readme_title.add_theme_constant_override("margin_left", 4)
	_readme_title.add_theme_constant_override("margin_right", 4)
	_readme_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL    # <-- add
	right_col.add_child(_readme_title)

	right_col.add_child(HSeparator.new())

	# Readme scroll + content
	var readme_scroll := ScrollContainer.new()
	readme_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL     # <-- add
	readme_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_col.add_child(readme_scroll)

	_readme_label = RichTextLabel.new()
	_readme_label.bbcode_enabled = true
	_readme_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_readme_label.scroll_active = false        # ScrollContainer handles scrolling
	_readme_label.selection_enabled = true
	_readme_label.add_theme_constant_override("line_separation", 4)
	_readme_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL     # <-- add
	_readme_label.size_flags_vertical = Control.SIZE_EXPAND_FILL       # <-- add
	_readme_label.fit_content = false                                   # <-- important: let it wrap to container width

	# Optional but helpful on dark bg:
	_readme_label.add_theme_color_override("default_color", Color(1,1,1))

	readme_scroll.add_child(_readme_label)


	# FOOTER
	root.add_child(HSeparator.new())

	var back := Button.new()
	back.text = "Back"
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(func():
		get_tree().change_scene_to_file("res://Scenes/TitleScreen.tscn")
	)
	root.add_child(back)

	# Optional: show the first tutorial by default
	if _tutorials.size() > 0:
		_populate_readme(_tutorials[0].key, _tutorials[0].title)

# ---------------- LIST ROW ----------------
func _make_tutorial_row(tkey: String, title_text: String, desc_text: String, completed: bool) -> Control:
	var card := VBoxContainer.new()
	card.add_theme_constant_override("separation", 4)

	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 8)
	card.add_child(title_row)

	var title := Label.new()
	title.text = title_text
	title.custom_minimum_size = Vector2(220, 0)
	title.add_theme_constant_override("margin_left", 8)
	title.add_theme_constant_override("margin_right", 8)
	title_row.add_child(title)

	var done := CheckBox.new()
	done.text = "Completed"
	done.button_pressed = completed
	done.disabled = true
	done.add_theme_constant_override("margin_left", 8)
	done.add_theme_constant_override("margin_right", 8)
	title_row.add_child(done)

	var desc := Label.new()
	desc.text = desc_text
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	desc.add_theme_constant_override("margin_left", 8)
	desc.add_theme_constant_override("margin_right", 8)
	card.add_child(desc)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	actions.add_theme_constant_override("margin_left", 8) # inside padding
	card.add_child(actions)

	var start := Button.new()
	if completed:
		start.text = "Replay"
	else:
		start.text = "View"
	start.pressed.connect(func():
		_populate_readme(tkey, title_text)
	)
	actions.add_child(start)

	var mark := Button.new()
	if completed:
		mark.text = "Mark Unread"
	else:
		mark.text = "Mark Read"
	mark.pressed.connect(func():
		var now_completed := not _get_completed(tkey)
		_set_completed(tkey, now_completed)
		# Rebuild list to refresh labels/buttons
		_rebuild_list_only()
	)
	actions.add_child(mark)

	card.add_child(HSeparator.new())
	return card

func _rebuild_list_only() -> void:
	# Remove all rows and rebuild from _tutorials
	for c in _list_box.get_children():
		_list_box.remove_child(c)
		c.queue_free()
	for t in _tutorials:
		var completed := _get_completed(t.key)
		_list_box.add_child(_make_tutorial_row(t.key, t.title, t.desc, completed))

# ---------------- README POPULATOR ----------------
func _populate_readme(tkey: String, title_text: String) -> void:
	_readme_title.text = title_text

	var bb := str(_tutorial_bbcode.get(tkey, ""))
	# sanitize special glyphs that your font might not have
	bb = _normalize_glyphs(bb)
		
	if bb.is_empty():
		bb = (
			"[center][b]Mek VS Mek[/b][/center]\n"
			+ "[center]A futuristic, turn-based strategy game where you command a squad of high-tech mechs on a dynamic, procedurally generated battlefield.[/center]\n\n"
			+ _bb_controls() + "\n" + _bb_terrain() + "\n" + _bb_specials() + "\n" + _bb_push()
		)
	_readme_label.clear()
	_readme_label.parse_bbcode(bb)

# ---------------- PERSISTENCE ----------------
func _cfg() -> ConfigFile:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	return cfg

func _cfg_get(section: String, key: String, def_val) -> Variant:
	var cfg := _cfg()
	return cfg.get_value(section, key, def_val)

func _cfg_set(section: String, key: String, val) -> void:
	var cfg := _cfg()
	cfg.set_value(section, key, val)
	cfg.save(SETTINGS_PATH)

func _get_completed(key: String) -> bool:
	return bool(_cfg_get("tutorials", key, false))

func _set_completed(key: String, state: bool) -> void:
	_cfg_set("tutorials", key, state)

func mark_completed(key: String) -> void:
	_set_completed(key, true)

# ---------------- README SECTIONS ----------------
func _bb_controls() -> String:
	return (
		"[b]Controls[/b]\n"
		+ "• Left-click / Tap: Select a unit\n"
		+ "• Right-click / Hold: Toggle Attack view & aim\n"
		+ "• Scroll wheel: Zoom the camera\n"
		+ "• Click a highlighted tile: Move there\n"
		+ "• Click an enemy in red range: Attack\n"
	)

func _bb_terrain() -> String:
	return (
		"[b]Terrain Effects[/b]\n"
		+ "• Grass: Recover +5 HP at turn end\n"
		+ "• Snow: −1 Attack Range while standing on it\n"
		+ "• Ice: −2 Attack Range and may slip\n"
		+ "• Road (↘ / ↙): +1 Movement this turn\n"
		+ "• Intersection: +2 Movement this turn\n"
	)

func _bb_specials() -> String:
	return (
		"[b]Special Abilities[/b] — click a target within range\n"
		+ "• Ground Slam: Leap and shockwave; damages all 8 adjacent tiles.\n"
		+ "• Mark & Pounce: Mark a target, then vault in for a heavy strike.\n"
		+ "• High-Arcing Shot: Shell lands after 2 s in a 3×3 zone (big center hit, splash around).\n"
		+ "• Suppressive Fire: Projectiles along lines up to 3 tiles per direction; damages and suppresses foes.\n"
		+ "• Guardian Halo: Grant a 1-round shield to an ally (lost if you whiff).\n"
		+ "• Fortify: Halve incoming damage until your next turn and fire a brief counter-barrage.\n"
		+ "• Heavy Rain: Call a focused missile pattern that saturates the impact zone.\n"
		+ "• Web Field: Threaded explosives travel a line, then burst in a 3×3.\n"
	)

func _bb_push() -> String:
	return (
		"[b]Push Mechanic[/b]\n"
		+ "Shove enemies into hazards to delete them instantly—water tiles, off-map edges, or straight into structures (collisions deal extra damage).\n"
	)

func _normalize_glyphs(s: String) -> String:
	# Replace fancy punctuation with safe ASCII fallbacks if font lacks them
	return s\
		.replace("•", "- ")\
		.replace("−", "-")\
		.replace("×", "x")

func _make_card_style(bg := Color(0.1, 0.1, 0.1), border := Color(1, 1, 1)) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_left = 8
	sb.corner_radius_bottom_right = 8
	sb.shadow_size = 8
	sb.shadow_color = Color(0, 0, 0, 0.35)
	return sb

func _apply_button_states_to_theme(theme: Theme) -> void:
	# Subtle hover/focus like Settings
	var base := StyleBoxFlat.new()
	base.bg_color = Color(0.18, 0.18, 0.18)
	base.corner_radius_top_left = 6
	base.corner_radius_top_right = 6
	base.corner_radius_bottom_left = 6
	base.corner_radius_bottom_right = 6
	base.content_margin_left = 10
	base.content_margin_right = 10
	base.content_margin_top = 6
	base.content_margin_bottom = 6

	var hover := base.duplicate()
	hover.bg_color = Color(0.22, 0.22, 0.22)

	var pressed := base.duplicate()
	pressed.bg_color = Color(0.14, 0.14, 0.14)
	pressed.border_width_all = 1
	pressed.border_color = Color(1,1,1,0.15)

	var focus := base.duplicate()
	focus.bg_color = base.bg_color
	focus.border_width_all = 2
	focus.border_color = Color(1,1,1,0.35)

	theme.set_stylebox("normal", "Button", base)
	theme.set_stylebox("hover", "Button", hover)
	theme.set_stylebox("pressed", "Button", pressed)
	theme.set_stylebox("focus", "Button", focus)

	# CheckBox/OptionButton for consistency
	theme.set_stylebox("normal", "CheckBox", base)
	theme.set_stylebox("hover", "CheckBox", hover)
	theme.set_stylebox("focus", "CheckBox", focus)
	theme.set_stylebox("normal", "OptionButton", base)
	theme.set_stylebox("hover", "OptionButton", hover)
	theme.set_stylebox("focus", "OptionButton", focus)
