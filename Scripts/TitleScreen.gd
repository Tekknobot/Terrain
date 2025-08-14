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
	get_tree().change_scene_to_file("res://Scenes/TutorialMenu.tscn")

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
		_cfg_get("video", "window_mode", 0),
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

	gameplay.add_child(_make_slider_row(
		"Mouse sensitivity",
		1, 200, 1,
		_cfg_get("gameplay", "mouse_sens", 100),
		func(v):
			_cfg_set("gameplay", "mouse_sens", int(v))
	))

	var invy := CheckBox.new()
	invy.text = "Invert Y axis"
	invy.add_theme_constant_override("margin_left", 8)
	invy.add_theme_constant_override("margin_right", 8)
	invy.button_pressed = _cfg_get("gameplay", "invert_y", false)
	invy.toggled.connect(func(on):
		_cfg_set("gameplay", "invert_y", on)
	)
	gameplay.add_child(invy)

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
	var wm := int(_cfg_get("video", "window_mode", 0))
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
