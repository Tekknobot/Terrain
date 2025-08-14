extends Control

# Get references to the UI elements.
@onready var play_button = $CenterContainer/VBoxContainer/Play
@onready var multiplayer_button = $CenterContainer/VBoxContainer/Multiplayer
@onready var quit_button = $CenterContainer/VBoxContainer/Quit
@onready var tutorial_button = $CenterContainer/VBoxContainer/Tutorials
# === NEW
@onready var settings_button = $CenterContainer/VBoxContainer/Settings

# === NEW: we’ll build a simple settings popup in code
var settings_window: Window

# === NEW: tutorials popup window handle
var tutorials_window: Window

# === NEW: tutorials data and runtime vars
var _tutorials := [
	{"key": "basics", "title": "Basics", "desc": "Movement, camera, and basic interaction."},
	{"key": "combat", "title": "Combat", "desc": "Attacking, blocking, abilities, and stamina."},
	{"key": "squad", "title": "Squad & Upgrades", "desc": "Selecting units, roles, and upgrading gear."},
	{"key": "ai", "title": "A.I. Mechanics", "desc": "How enemy turns, specials, and targeting work."}  # ← NEW
]

var _tutorial_bbcode := {}               # built on window creation
var _list_box: VBoxContainer             # left list (inside window)
var _readme_title: Label                 # right title
var _readme_label: RichTextLabel         # right content

var _selector: OptionButton

func _ready() -> void:
	play_button.grab_focus()

	play_button.pressed.connect(_on_PlayButton_pressed)
	quit_button.pressed.connect(_on_QuitButton_pressed)	
	tutorial_button.pressed.connect(_on_TutorialButton_pressed)
	# === NEW
	settings_button.pressed.connect(_on_SettingsButton_pressed)

func _on_PlayButton_pressed() -> void:
	get_tree().change_scene_to_file("res://Scenes/SquadSelect.tscn")

func _on_QuitButton_pressed() -> void:
	get_tree().quit()

func _on_reset_pressed() -> void:
	GameData.last_enemy_upgrade_level = 0
	GameData.play_reset()
	get_tree().change_scene_to_file("res://Scenes/SquadSelect.tscn")

func _on_TutorialButton_pressed() -> void:
	if tutorials_window == null:
		tutorials_window = _build_tutorials_window(
			"res://Fonts/magofonts/mago1.ttf", 16,
			"res://Fonts/magofonts/mago3.ttf", 20
		)
		add_child(tutorials_window)
	tutorials_window.popup_centered()

func _build_tutorials_window(
		font_path: String = "res://Fonts/magofonts/mago1.ttf",
		font_size: int = 16,
		heading_font_path: String = "",
		heading_font_size: int = 28
	) -> Window:

	# --- window shell (smaller) ---
	var win := Window.new()
	win.title = ""
	win.size = Vector2i(600, 480)
	win.unresizable = false

	# Allow top-right X button to close window
	win.close_requested.connect(func():
		win.hide()
	)

	# --- card matching Settings ---
	var root_holder := VBoxContainer.new()
	root_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	win.add_child(root_holder)

	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _make_card_style())
	root_holder.add_child(card)

	var card_pad := MarginContainer.new()
	card_pad.add_theme_constant_override("margin_left", 8)
	card_pad.add_theme_constant_override("margin_right", 8)
	card_pad.add_theme_constant_override("margin_top", 8)
	card_pad.add_theme_constant_override("margin_bottom", 8)
	card.add_child(card_pad)

	var outer := MarginContainer.new()
	outer.add_theme_constant_override("margin_left", 20)
	outer.add_theme_constant_override("margin_right", 20)
	outer.add_theme_constant_override("margin_top", 16)
	outer.add_theme_constant_override("margin_bottom", 16)
	card_pad.add_child(outer)

	var root := VBoxContainer.new()
	root.custom_minimum_size = Vector2(540, 380)
	root.add_theme_constant_override("separation", 10)
	outer.add_child(root)

	# --- theme (fonts + button states) ---
	var theme := Theme.new()
	if ResourceLoader.exists(font_path):
		var body_font := load(font_path) as FontFile
		if body_font:
			theme.set_default_font(body_font)
			theme.set_default_font_size(font_size)
	_apply_button_states_to_theme(theme)
	root.theme = theme

	var heading_font: FontFile
	if heading_font_path != "" and ResourceLoader.exists(heading_font_path):
		heading_font = load(heading_font_path) as FontFile

	# --- title ---
	var title := Label.new()
	title.text = "Tutorials"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if heading_font:
		title.add_theme_font_override("font", heading_font)
		title.add_theme_font_size_override("font_size", heading_font_size)
	root.add_child(title)

	root.add_child(HSeparator.new())

	# ------------------------------
	# Toolbar: selector + actions
	# ------------------------------
	var toolbar := HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 8)
	root.add_child(toolbar)

	_selector = OptionButton.new()
	_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for i in _tutorials.size():
		var t = _tutorials[i]
		_selector.add_item(t.title, i)
	toolbar.add_child(_selector)

	# ------------------------------
	# Content area
	# ------------------------------
	# Content header
	root.add_child(HSeparator.new())

	_readme_title = Label.new()
	_readme_title.text = "Select a tutorial"
	_readme_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(_readme_title)

	# Scrollable content
	var readme_scroll := ScrollContainer.new()
	readme_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	readme_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	readme_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	readme_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	root.add_child(readme_scroll)

	_readme_label = RichTextLabel.new()
	_readme_label.bbcode_enabled = true
	_readme_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_readme_label.scroll_active = false   # ScrollContainer handles scrolling
	_readme_label.selection_enabled = true
	_readme_label.fit_content = true
	_readme_label.add_theme_constant_override("line_separation", 4)
	_readme_label.add_theme_color_override("default_color", Color(1,1,1))
	_readme_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_readme_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	readme_scroll.add_child(_readme_label)
	readme_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	readme_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	
	# Footer
	root.add_child(HSeparator.new())
	var close := Button.new()
	close.text = "Close"
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(win.hide)
	root.add_child(close)

	# --- build bbcode dictionary ---
	_tutorial_bbcode.clear()
	_tutorial_bbcode["ai"] = _bb_ai_mechanics()  # ← NEW
	_tutorial_bbcode["basics"] = _bb_controls() + "\n" + _bb_terrain() + "\n" + _bb_push()
	_tutorial_bbcode["combat"] = _bb_specials() + "\n"
	_tutorial_bbcode["squad"] = (
		""
		+ "• Upgrades are awarded after each map you clear, based on surviving units.\n"
		+ "• Select units that complement each other (ranged + brawler + utility).\n"
		+ "• Upgrades improve HP, range, abilities, and mobility.\n"
	)

	# --- signals / initial state ---
	_selector.item_selected.connect(func(idx):
		var t = _tutorials[idx]
		_populate_readme(t.key, t.title)
	)

	# default select first
	if _tutorials.size() > 0:
		_selector.select(0)
		var t0 = _tutorials[0]
		_populate_readme(t0.key, t0.title)

	return win
	
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
	actions.add_theme_constant_override("margin_left", 8)
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
		_rebuild_list_only()
	)
	actions.add_child(mark)


	card.add_child(HSeparator.new())
	return card

func _rebuild_list_only() -> void:
	if _list_box == null:
		return
	for c in _list_box.get_children():
		_list_box.remove_child(c)
		c.queue_free()
	for t in _tutorials:
		var completed := _get_completed(t.key)
		_list_box.add_child(_make_tutorial_row(t.key, t.title, t.desc, completed))

func _populate_readme(tkey: String, title_text: String) -> void:
	if _readme_title: _readme_title.text = title_text
	if _readme_label == null:
		return
	var bb := str(_tutorial_bbcode.get(tkey, ""))
	bb = _normalize_glyphs(bb)
	if bb.is_empty():
		bb = (
			"[center][b]Mek VS Mek[/b][/center]\n"
			+ "[center]A futuristic, turn-based strategy game where you command a squad of high-tech mechs on a dynamic, procedurally generated battlefield.[/center]\n\n"
			+ _bb_controls() + "\n" + _bb_terrain() + "\n" + _bb_specials() + "\n" + _bb_push()
		)
	_readme_label.clear()
	_readme_label.parse_bbcode(bb)

func _bb_controls() -> String:
	return (
		"[b]Controls[/b]\n"
		+ "• Left-click / Tap: Select a unit\n"
		+ "• Right-click / Hold: Toggle Attack view\n"
		+ "• Scroll wheel: Zoom the camera out or in\n"
		+ "• Click a highlighted tile: Move there\n"
		+ "• Click an enemy in red range: Attack\n"
	)

func _bb_terrain() -> String:
	return (
		"[b]Terrain Effects[/b]\n"
		+ "• Grass: Recover +5 HP at turn end\n"
		+ "• Snow: −1 Attack Range while standing on it\n"
		+ "• Ice: −2 Attack Range and may slip\n"
		+ "• Roads: +1 Movement this turn\n"
		+ "• Intersection: +2 Movement this turn\n"
	)

func _bb_specials() -> String:
	return (
		"[b]Special Abilities[/b] -- click a target within range\n"
		+ "• Ground Slam: Leap and shockwave; damages all 8 adjacent tiles.\n"
		+ "• Mark & Pounce: Mark a target, then vault in for a heavy strike.\n"
		+ "• High-Arcing Shot: Shell lands after 2 s in a 3×3 zone (big center hit, splash around).\n"
		+ "• Suppressive Fire: Projectiles along lines up to 3 tiles per direction; damages and suppresses foes.\n"
		+ "• Guardian Halo: Grant a 1-round shield to an ally (lost if you whiff).\n"
		+ "• Fortify: Halve incoming damage until your next turn and fire a brief counter-barrage.\n"
		+ "• Heavy Rain: Call a focused missile pattern that saturates the impact zone.\n"
		+ "• Web Field: Threaded explosives travel a line, then burst in a 3×3.\n"
	)

func _bb_ai_mechanics() -> String:
	return (
		"Turn Flow\n"
		+ "- The game alternates turns in this order: PLAYER -> ENEMY.\n"
		+ "- A turn starts with a signal that it has begun, then each unit of that team acts in sequence.\n"
		+ "- If one side has no units left, the turn ends early and victory or defeat is checked.\n"
		+ "\n"
		+ "Enemy Unit Action Order\n"
		+ "When it is the ENEMY team's turn, each enemy unit follows this pattern:\n"
		+ "1) If the unit has not moved or attacked yet, it may try to use a Special Ability.\n"
		+ "   - The choice is based on the unit type and battlefield situation.\n"
		+ "   - A random roll controls whether the special is actually used (60 percent chance).\n"
		+ "   - If used, the unit performs the action, marks itself as having moved and attacked, and ends its turn.\n"
		+ "2) If no special is used, it plans movement toward the closest enemy.\n"
		+ "   - Pathfinding chooses a route toward the target.\n"
		+ "   - Prefers stopping within attack range but not adjacent, keeping maximum safe distance.\n"
		+ "3) Executes movement.\n"
		+ "4) If still able to attack, it may attempt another special (same 60 percent chance).\n"
		+ "5) If no special is used, it attacks normally:\n"
		+ "   - Ranged or support units pick the closest target within range.\n"
		+ "   - Melee units attack if they are next to an enemy.\n"
		+ "\n"
		+ "Special Ability Selection by Unit Type\n"
		+ "- Vanguard: Ground Slam if a player unit is on any directly adjacent tile.\n"
		+ "- Aegis: Mark and Pounce if a player unit is within three tiles.\n"
		+ "- Tempest: Guardian Halo if an ally within five tiles has the lowest health, no shield, and is below 70 percent HP.\n"
		+ "- Titan: High-Arcing Shot aimed to hit the largest cluster of player units within five tiles (3x3 impact area).\n"
		+ "- Specter: Suppressive Fire if a player unit is directly adjacent in a straight line.\n"
		+ "- Nova: Fortify (self buff) if not already fortified.\n"
		+ "- Raptor: Heavy Rain (5x5 area) if it can hit at least one player unit within five tiles.\n"
		+ "- Valkyrie: Spider Blast against a player unit within five tiles.\n"
		+ "- If no condition is met, no special is chosen.\n"
		+ "\n"
		+ "Targeting and Ranged Logic\n"
		+ "- Ranged units target the closest enemy within their range.\n"
		+ "- If none are in range, they move to get within range if possible.\n"
		+ "\n"
		+ "Movement and Pathing\n"
		+ "- Enemies path toward the closest opposing unit.\n"
		+ "- When moving, they try to end on a tile that:\n"
		+ "  - Is within attack range of the target,\n"
		+ "  - Is not directly adjacent if ranged,\n"
		+ "  - Is the furthest valid step they can take that turn.\n"
		+ "\n"
		+ "Round End and Spawns\n"
		+ "- After the ENEMY turn finishes, a signal is sent that the round has ended.\n"
		+ "- At the end of the ENEMY turn, new enemy units may spawn before the next team begins.\n"
		+ "\n"
		+ "Game Over and Rewards\n"
		+ "- If either side has no units, the match ends immediately.\n"
		+ "- Rewards are based on total damage dealt, kills, and player losses, with survivors saved for the next battle.\n"
		+ "\n"
		+ "Tuning Options\n"
		+ "- The special ability chance (currently 60 percent) controls how often abilities are used when available.\n"
	)

func _bb_push() -> String:
	return (
		"[b]Push Mechanic[/b]\n"
		+ "Shove enemies into hazards to delete them instantly -- water tiles, off-map edges, or straight into structures (collisions deal extra damage).\n"
	)

func _normalize_glyphs(s: String) -> String:
	return s.replace("•", "- ").replace("−", "-").replace("×", "x")

# persistence (uses your SETTINGS_PATH and _cfg helpers already in this file)
func _get_completed(key: String) -> bool:
	return bool(_cfg_get("tutorials", key, false))

func _set_completed(key: String, state: bool) -> void:
	_cfg_set("tutorials", key, state)

func mark_completed(key: String) -> void:
	_set_completed(key, true)

# === NEW ===
func _on_SettingsButton_pressed() -> void:
	if settings_window == null:
		settings_window = _build_settings_window(
			"res://Fonts/magofonts/mago1.ttf", 16,
			"res://Fonts/magofonts/mago3.ttf", 20
		)
		add_child(settings_window)
	settings_window.popup_centered()

const SETTINGS_PATH := "user://settings.cfg"

func _build_settings_window(
		font_path: String = "res://Fonts/magofonts/mago3.ttf",
		font_size: int = 16,
		heading_font_path: String = "",
		heading_font_size: int = 32
	) -> Window:
	var win := Window.new()
	win.title = ""
	win.size = Vector2i(520, 400)

	# Top-level margin so nothing touches the window edges
	var outer := MarginContainer.new()
	outer.add_theme_constant_override("margin_left", 20)
	outer.add_theme_constant_override("margin_right", 20)
	outer.add_theme_constant_override("margin_top", 16)
	outer.add_theme_constant_override("margin_bottom", 16)
	win.add_child(outer)

	var root := VBoxContainer.new()
	root.custom_minimum_size = Vector2(480, 320)
	root.add_theme_constant_override("separation", 12)
	outer.add_child(root)

	# Font theme (so every child inherits)
	var theme := Theme.new()
	if ResourceLoader.exists(font_path):
		var body_font := load(font_path) as FontFile
		if body_font:
			theme.set_default_font(body_font)
			theme.set_default_font_size(font_size)

	# 👉 make Settings buttons (including Close) match the rest
	_apply_button_states_to_theme(theme)
			
	root.theme = theme

	# Optional heading font
	var heading_font: FontFile
	if heading_font_path != "" and ResourceLoader.exists(heading_font_path):
		heading_font = load(heading_font_path) as FontFile

	# Title
	var title := Label.new()
	title.text = "Settings"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_constant_override("margin_left", 8)
	title.add_theme_constant_override("margin_right", 8)
	if heading_font:
		title.add_theme_font_override("font", heading_font)
		title.add_theme_font_size_override("font_size", heading_font_size)
	root.add_child(title)

	var sep := HSeparator.new()
	root.add_child(sep)

	# Tabs
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(tabs)

	# --------------------
	# AUDIO TAB
	# --------------------
	var audio_pad := MarginContainer.new()
	audio_pad.add_theme_constant_override("margin_left", 8)
	audio_pad.add_theme_constant_override("margin_right", 8)
	audio_pad.add_theme_constant_override("margin_top", 6)
	audio_pad.add_theme_constant_override("margin_bottom", 6)
	var audio := VBoxContainer.new()
	audio.add_theme_constant_override("separation", 10)
	audio_pad.add_child(audio)
	tabs.add_child(audio_pad)
	tabs.set_tab_title(tabs.get_tab_count() - 1, "Audio")

	audio.add_child(_make_slider_row(
		"Master volume",
		0, 100, 1,
		int(round(_get_bus_volume_linear("Master") * 100.0)),
		func(v):
			_set_bus_volume_linear("Master", v / 100.0)
			_cfg_set("audio", "master", float(v) / 100.0)
	))

	audio.add_child(_make_slider_row(
		"Music volume",
		0, 100, 1,
		int(round(MusicManager.get_volume_linear() * 100.0)),
		func(v):
			MusicManager.set_volume_linear(v / 100.0)
			_cfg_set("audio", "music", float(v) / 100.0)
	))

	audio.add_child(_make_slider_row(
		"SFX volume",
		0, 100, 1,
		int(round(_get_bus_volume_linear("SFX") * 100.0)),
		func(v):
			_set_bus_volume_linear("SFX", v / 100.0)
			_cfg_set("audio", "sfx", float(v) / 100.0)
	))

	var mute := CheckBox.new()
	mute.text = "Mute music"
	mute.add_theme_constant_override("margin_left", 8)
	mute.add_theme_constant_override("margin_right", 8)
	mute.button_pressed = _cfg_get("audio", "music_muted", MusicManager.is_muted())
	mute.toggled.connect(func(on):
		MusicManager.set_muted(on)
		_cfg_set("audio", "music_muted", on)
	)
	audio.add_child(mute)

	# --------------------
	# VIDEO TAB
	# --------------------
	var video_pad := MarginContainer.new()
	video_pad.add_theme_constant_override("margin_left", 8)
	video_pad.add_theme_constant_override("margin_right", 8)
	video_pad.add_theme_constant_override("margin_top", 6)
	video_pad.add_theme_constant_override("margin_bottom", 6)
	var video := VBoxContainer.new()
	video.add_theme_constant_override("separation", 10)
	video_pad.add_child(video)
	tabs.add_child(video_pad)
	tabs.set_tab_title(tabs.get_tab_count() - 1, "Video")

	var wmodes := ["Windowed", "Borderless", "Fullscreen"]
	video.add_child(_make_option_row(
		"Window mode",
		wmodes,
		_get_current_window_mode_index(),  # ← reflect current state
		func(idx):
			if idx == 0:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
				DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
			elif idx == 1:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
				DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
			elif idx == 2:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
				DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
			_cfg_set("video", "window_mode", idx)
	))

	var vsync := CheckBox.new()
	vsync.text = "VSync"
	vsync.add_theme_constant_override("margin_left", 8)
	vsync.add_theme_constant_override("margin_right", 8)
	vsync.button_pressed = _cfg_get("video", "vsync", true)
	vsync.toggled.connect(func(on):
		if on:
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
		else:
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		_cfg_set("video", "vsync", on)
	)
	video.add_child(vsync)

	video.add_child(_make_slider_row(
		"Max FPS (0 = uncapped)",
		0, 240, 10,
		_cfg_get("video", "max_fps", 0),
		func(v):
			Engine.max_fps = int(v)
			_cfg_set("video", "max_fps", int(v))
	))

	# --------------------
	# GAMEPLAY TAB
	# --------------------
	var gameplay_pad := MarginContainer.new()
	gameplay_pad.add_theme_constant_override("margin_left", 8)
	gameplay_pad.add_theme_constant_override("margin_right", 8)
	gameplay_pad.add_theme_constant_override("margin_top", 6)
	gameplay_pad.add_theme_constant_override("margin_bottom", 6)
	var gameplay := VBoxContainer.new()
	gameplay.add_theme_constant_override("separation", 10)
	gameplay_pad.add_child(gameplay)
	tabs.add_child(gameplay_pad)
	tabs.set_tab_title(tabs.get_tab_count() - 1, "Gameplay")

	# Camera Shake
	var camshake := CheckBox.new()
	camshake.text = "Enable Camera Shake"
	camshake.add_theme_constant_override("margin_left", 8)
	camshake.add_theme_constant_override("margin_right", 8)
	camshake.button_pressed = _cfg_get("gameplay", "camera_shake", true)
	camshake.toggled.connect(func(on):
		_cfg_set("gameplay", "camera_shake", on)
	)
	gameplay.add_child(camshake)

	# Footer buttons
	var sep2 := HSeparator.new()
	root.add_child(sep2)

	var close := Button.new()
	close.text = "Close"
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(win.hide)
	root.add_child(close)

	# Apply saved settings now
	_apply_settings_from_cfg()

	return win


# ------- Small UI builders -------
func _make_slider_row(label_text: String, min_v: int, max_v: int, step: int, start_value: int, on_change: Callable) -> Control:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 8)

	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(220, 0)
	lbl.add_theme_constant_override("margin_left", 8)
	lbl.add_theme_constant_override("margin_right", 8)
	row.add_child(lbl)

	var slider := HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = step
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value = start_value
	slider.value_changed.connect(func(v): on_change.call(v))
	row.add_child(slider)

	var val := Label.new()
	val.custom_minimum_size = Vector2(60, 0)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val.add_theme_constant_override("margin_left", 8)
	val.add_theme_constant_override("margin_right", 8)
	val.text = str(int(slider.value))
	slider.value_changed.connect(func(v): val.text = str(int(v)))
	row.add_child(val)

	return row


func _make_option_row(label_text: String, items: PackedStringArray, start_idx: int, on_change: Callable) -> Control:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 8)

	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(220, 0)
	lbl.add_theme_constant_override("margin_left", 8)
	lbl.add_theme_constant_override("margin_right", 8)
	row.add_child(lbl)

	var opt := OptionButton.new()
	for i in items.size():
		opt.add_item(items[i], i)
	opt.select(clamp(start_idx, 0, items.size() - 1))
	opt.item_selected.connect(func(idx): on_change.call(idx))
	row.add_child(opt)

	return row

# ------- Config persistence -------
func _cfg() -> ConfigFile:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH) # OK if missing
	return cfg

func _cfg_get(section: String, key: String, def_val) -> Variant:
	var cfg := _cfg()
	return cfg.get_value(section, key, def_val)

func _cfg_set(section: String, key: String, val) -> void:
	var cfg := _cfg()
	cfg.set_value(section, key, val)
	cfg.save(SETTINGS_PATH)

func _apply_settings_from_cfg() -> void:
	# Audio
	var master := float(_cfg_get("audio", "master", _get_bus_volume_linear("Master")))
	_set_bus_volume_linear("Master", master)
	var music := float(_cfg_get("audio", "music", MusicManager.get_volume_linear()))
	MusicManager.set_volume_linear(music)
	var sfx := float(_cfg_get("audio", "sfx", _get_bus_volume_linear("SFX")))
	_set_bus_volume_linear("SFX", sfx)
	MusicManager.set_muted(bool(_cfg_get("audio", "music_muted", MusicManager.is_muted())))

	# Video
	var wm := int(_cfg_get("video", "window_mode", 2))
	match wm:
		0:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
		1:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
		2:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

	var res_idx := int(_cfg_get("video", "resolution_idx", 2))
	var resolutions := PackedStringArray(["1280 x 720","1600 x 900","1920 x 1080","2560 x 1440"])
	res_idx = clamp(res_idx, 0, resolutions.size()-1)
	var parts := resolutions[res_idx].split(" x ")
	if parts.size() == 2:
		DisplayServer.window_set_size(Vector2i(int(parts[0]), int(parts[1])))

	var vs := bool(_cfg_get("video", "vsync", true))
	if vs:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	else:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)

	Engine.max_fps = int(_cfg_get("video", "max_fps", 0))

	# Gameplay / UI
	var sens := int(_cfg_get("gameplay", "mouse_sens", 100))
	_cfg_set("gameplay", "mouse_sens", sens) # ensure exists
	get_tree().root.content_scale_factor = float(_cfg_get("ui", "scale_percent", 100)) / 100.0
	var locale_idx := int(_cfg_get("ui", "locale_idx", 0))
	var locales := PackedStringArray(["en","fr","es","de"])
	locale_idx = clamp(locale_idx, 0, locales.size()-1)
	TranslationServer.set_locale(locales[locale_idx])

# ------- Audio bus helpers -------
func _get_bus_volume_linear(bus_name: String) -> float:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return 1.0
	var db := AudioServer.get_bus_volume_db(idx)
	# Avoid -INF; clamp to silence floor
	if db <= -80.0:
		return 0.0
	return db_to_linear(db)

func _set_bus_volume_linear(bus_name: String, v: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return
	v = clamp(v, 0.0, 1.0)
	if v <= 0.001:
		AudioServer.set_bus_volume_db(idx, -80.0)
	else:
		AudioServer.set_bus_volume_db(idx, linear_to_db(v))

func _make_card_style(bg := Color(0, 0, 0), border := Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg               # nearly black background
	sb.border_color = border       # invisible border
	sb.border_width_left = 0
	sb.border_width_top = 0
	sb.border_width_right = 0
	sb.border_width_bottom = 0
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_left = 8
	sb.corner_radius_bottom_right = 8
	sb.shadow_size = 8
	sb.shadow_color = Color(0, 0, 0, 0.5)  # keep soft shadow for depth
	return sb

func _apply_button_states_to_theme(theme: Theme) -> void:
	# ---------- Base button style ----------
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

	var hover := base.duplicate();   hover.bg_color = Color(0.22, 0.22, 0.22)
	var pressed := base.duplicate(); pressed.bg_color = Color(0.14, 0.14, 0.14)
	var focus := base.duplicate();   focus.bg_color = base.bg_color
	var disabled := base.duplicate(); disabled.bg_color = Color(0.18, 0.18, 0.18, 0.6)

	# Buttons / OptionButtons
	for cls in ["Button", "OptionButton"]:
		theme.set_stylebox("normal", cls, base)
		theme.set_stylebox("hover",  cls, hover)
		theme.set_stylebox("pressed",cls, pressed)
		theme.set_stylebox("focus",  cls, focus)
		theme.set_stylebox("disabled", cls, disabled)

	# ---------- CheckBox ----------
	var pad_x := 10
	var with_checkbox_padding = func(sbx: StyleBoxFlat) -> StyleBoxFlat:
		var s := sbx.duplicate()
		s.content_margin_left  = base.content_margin_left  + pad_x
		s.content_margin_right = base.content_margin_right + pad_x
		s.content_margin_top   = base.content_margin_top
		s.content_margin_bottom= base.content_margin_bottom
		return s

	var cb_states := {
		"normal":   with_checkbox_padding.call(base),
		"hover":    with_checkbox_padding.call(hover),
		"pressed":  with_checkbox_padding.call(pressed),
		"focus":    with_checkbox_padding.call(focus),
		"disabled": with_checkbox_padding.call(disabled),
		"hover_pressed": with_checkbox_padding.call(pressed)
	}

	for state in cb_states.keys():
		theme.set_stylebox(state, "CheckBox", cb_states[state])

	theme.set_constant("h_separation",  "CheckBox", 8)
	theme.set_constant("check_vadjust", "CheckBox", 0)
	theme.set_font("font", "CheckBox", theme.get_default_font())
	theme.set_font_size("font_size", "CheckBox", theme.get_default_font_size())

func _get_current_window_mode_index() -> int:
	var mode := DisplayServer.window_get_mode()
	if mode == DisplayServer.WINDOW_MODE_FULLSCREEN:
		return 2
	var borderless := DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_BORDERLESS)
	if borderless:
		return 1
	else:
		return 0
