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
	# Center everything on screen
	var center := CenterContainer.new()
	add_child(center)

	# OUTER MARGINS inside center
	var outer := MarginContainer.new()
	outer.add_theme_constant_override("margin_left", 20)
	outer.add_theme_constant_override("margin_right", 20)
	outer.add_theme_constant_override("margin_top", 16)
	outer.add_theme_constant_override("margin_bottom", 16)
	center.add_child(outer)

	# ROOT COLUMN
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
	card.add_child(actions)

	var start := Button.new()
	if completed:
		start.text = "Replay"
	else:
		start.text = "Start"
	start.pressed.connect(func():
		_populate_readme(tkey, title_text)
	)
	actions.add_child(start)

	var mark := Button.new()
	if completed:
		mark.text = "Mark Incomplete"
	else:
		mark.text = "Mark Complete"
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
		+ "• Left-click (or tap) to select a unit\n"
		+ "• Right-click (or hold) to enter attack mode\n"
		+ "• Scroll Wheel to zoom\n"
	)

func _bb_terrain() -> String:
	return (
		"[b]Terrain Effects[/b]\n"
		+ "• Grass: +5 HP when standing on it\n"
		+ "• Snow: −1 attack range\n"
		+ "• Ice: −2 attack range\n"
		+ "• Road (Down-Right / Down-Left): +1 movement\n"
		+ "• Intersection: +2 movement\n"
	)

func _bb_specials() -> String:
	return (
		"[b]Special Abilities[/b] (click a target within range)\n"
		+ "• Ground Slam: Shockwaves damage all adjacent tiles (even empty ones).\n"
		+ "• Mark & Pounce: Lock onto a target tile, leap in, and deliver a lethal strike.\n"
		+ "• High-Arcing Shot: Parabolic shell lands after 2 s in a 3×3 zone—heavy center damage, splash around.\n"
		+ "• Suppressive Fire: Line of fire up to 4 tiles—enemies in the path take damage.\n"
		+ "• Guardian Halo: Grant a one-round shield to an ally (lost if you miss).\n"
		+ "• Fortify: Halve all incoming damage until your next turn.\n"
		+ "• Heavy Rain: Call down a devastating missile barrage on the battlefield.\n"
		+ "• Web Field: Explosives ensnare and damage all foes in the zone.\n"
	)

func _bb_push() -> String:
	return (
		"[b]Push Mechanic[/b]\n"
		+ "Knock enemies into hazards—water tiles, off-map edges or obstacles—for instant elimination.\n"
	)

func _normalize_glyphs(s: String) -> String:
	# Replace fancy punctuation with safe ASCII fallbacks if font lacks them
	return s\
		.replace("•", "- ")\
		.replace("−", "-")\
		.replace("×", "x")
