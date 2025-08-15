extends Control

# =========================
# Defeat Popup (Control root)
# =========================

signal continue_requested
signal quit_requested

@export var title_screen_path := "res://Scenes/TitleScreen.tscn"  # where Quit should go

var defeat_window: Window
var _defeat_msg_label: Label
var _defeat_on_continue: Callable = Callable() # optional continue callback

func _ready() -> void:
	# (Optional) quick test
	show_defeat_popup("You have been defeated. Try again?", func(): _reload_or_restart())

# Public API: call this when the player loses
func show_defeat_popup(
		message: String = "You have been defeated.",
		on_continue: Callable = Callable()
	) -> void:
	if defeat_window == null:
		defeat_window = _build_defeat_window(
			"res://Fonts/magofonts/mago1.ttf", 16,   # body font
			"res://Fonts/magofonts/mago3.ttf", 32    # heading font
		)
		add_child(defeat_window)

	_defeat_on_continue = on_continue

	if _defeat_msg_label:
		_defeat_msg_label.text = message

	defeat_window.popup_centered()
	var cont_btn := defeat_window.get_node("Root/CardPad/Outer/Root/Buttons/Continue") as Button
	if cont_btn:
		cont_btn.grab_focus()

# --------------------
# Window build
# --------------------
func _build_defeat_window(
		font_path: String,
		font_size: int,
		heading_font_path: String,
		heading_font_size: int
	) -> Window:
	var win := Window.new()
	win.title = ""
	win.size = Vector2i(520, 260)
	win.unresizable = false
	win.min_size = win.size
	win.close_requested.connect(func(): win.hide())

	# Hierarchy matching your title-screen card look
	var root_holder := VBoxContainer.new()
	root_holder.name = "Root"
	root_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root_holder.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	win.add_child(root_holder)

	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _make_card_style())
	root_holder.add_child(card)

	var card_pad := MarginContainer.new()
	card_pad.name = "CardPad"
	card_pad.add_theme_constant_override("margin_left", 8)
	card_pad.add_theme_constant_override("margin_right", 8)
	card_pad.add_theme_constant_override("margin_top", 8)
	card_pad.add_theme_constant_override("margin_bottom", 8)
	card.add_child(card_pad)

	var outer := MarginContainer.new()
	outer.name = "Outer"
	outer.add_theme_constant_override("margin_left", 20)
	outer.add_theme_constant_override("margin_right", 20)
	outer.add_theme_constant_override("margin_top", 16)
	outer.add_theme_constant_override("margin_bottom", 16)
	card_pad.add_child(outer)

	var root := VBoxContainer.new()
	root.name = "Root"
	root.custom_minimum_size = Vector2(460, 180)
	root.add_theme_constant_override("separation", 10)
	outer.add_child(root)

	# Theme (fonts + button states) — mirrors title screen
	var theme := Theme.new()
	if ResourceLoader.exists(font_path):
		var body := load(font_path) as FontFile
		if body:
			theme.set_default_font(body)
			theme.set_default_font_size(font_size)
	_apply_button_states_to_theme(theme)
	root.theme = theme

	var heading_font: FontFile
	if heading_font_path != "" and ResourceLoader.exists(heading_font_path):
		heading_font = load(heading_font_path) as FontFile

	# Title
	var title := Label.new()
	title.text = "Defeat"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if heading_font:
		title.add_theme_font_override("font", heading_font)
		title.add_theme_font_size_override("font_size", heading_font_size)
	root.add_child(title)

	root.add_child(HSeparator.new())

	# Message
	_defeat_msg_label = Label.new()
	_defeat_msg_label.name = "Msg"
	_defeat_msg_label.text = "You have been defeated."
	_defeat_msg_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_defeat_msg_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_defeat_msg_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_defeat_msg_label.add_theme_constant_override("margin_left", 8)
	_defeat_msg_label.add_theme_constant_override("margin_right", 8)
	root.add_child(_defeat_msg_label)

	# Buttons
	root.add_child(HSeparator.new())
	var buttons := HBoxContainer.new()
	buttons.name = "Buttons"
	buttons.add_theme_constant_override("separation", 10)
	buttons.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(buttons)

	var spacer_l := Control.new(); spacer_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var spacer_r := Control.new(); spacer_r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(spacer_l)

	var continue_btn := Button.new()
	continue_btn.name = "Continue"
	continue_btn.text = "Continue"
	continue_btn.custom_minimum_size = Vector2(120, 0)
	continue_btn.pressed.connect(_on_defeat_continue_pressed)
	buttons.add_child(continue_btn)

	var quit_btn := Button.new()
	quit_btn.name = "Quit"
	quit_btn.text = "Quit"
	quit_btn.custom_minimum_size = Vector2(120, 0)
	quit_btn.pressed.connect(_on_defeat_quit_pressed)
	buttons.add_child(quit_btn)

	buttons.add_child(spacer_r)

	return win

# --------------------
# Button handlers
# --------------------
func _on_defeat_continue_pressed() -> void:
	if _defeat_on_continue.is_valid():
		_defeat_on_continue.call()
	elif is_connected("continue_requested", self._dummy):
		emit_signal("continue_requested")
	else:
		_reload_or_restart()  # ← reload current scene
	defeat_window.hide()

func _on_defeat_quit_pressed() -> void:
	# Go back to Title Screen
	if is_connected("quit_requested", self._dummy):
		emit_signal("quit_requested")
	get_tree().change_scene_to_file(title_screen_path)

# Default fallback continue action
func _reload_or_restart() -> void:
	# Try to reload current scene; if not possible, quit as last resort.
	if get_tree().current_scene:
		get_tree().reload_current_scene()
	else:
		get_tree().quit()

func _dummy() -> void: pass

# --------------------
# Styling helpers (copied to match your title-screen look)
# If you already have these globally, you can delete these local copies.
# --------------------
func _make_card_style(bg := Color(0, 0, 0), border := Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.border_width_left = 0
	sb.border_width_top = 0
	sb.border_width_right = 0
	sb.border_width_bottom = 0
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_left = 8
	sb.corner_radius_bottom_right = 8
	sb.shadow_size = 8
	sb.shadow_color = Color(0, 0, 0, 0.5)
	return sb

func _apply_button_states_to_theme(theme: Theme) -> void:
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

	for cls in ["Button", "OptionButton"]:
		theme.set_stylebox("normal", cls, base)
		theme.set_stylebox("hover",  cls, hover)
		theme.set_stylebox("pressed",cls, pressed)
		theme.set_stylebox("focus",  cls, focus)
		theme.set_stylebox("disabled", cls, disabled)

	# CheckBox to match if you ever add one here
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
