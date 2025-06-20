extends Node2D

signal region_selected(index, name)

@export var max_depth: int = 5             # e.g. to reach “Grandmaster” at depth 5
@export var branches_per_node: int = 1
@export var branch_length: float = 300.0
@export var length_variance: float = 0.0
@export var angle_spread: float = 90.0
@export var region_radius: float = 16.0
@export var region_font: Font

# One texture *per* tier, in tier‐order:
# [Novice, Apprentice, Adept, Expert, Master, Grandmaster, …]
@export var region_textures: Array[Texture2D] = []

var difficulty_tiers: Dictionary = {
	1: "Novice",      2: "Apprentice", 3: "Adept",
	4: "Expert",      5: "Master",     6: "Grandmaster",
	7: "Legendary",   8: "Mythic",     9: "Transcendent",
	10: "Celestial", 11: "Divine",   12: "Omnipotent"
}

@export var region_names: Array = [
	"Ironhold","Gearfall","Steelforge","Rusthaven","Cinderwall",
	"Forgekeep","Pulsegate","Hammerfall","Blastmoor","Magnetar",
	"Titanreach","Axlepoint","Vulcannon","Boltspire","Mecharis",
	"Lockridge","Quakefield","Junktown","Arcforge","ZeroCore",
	"Crankton","Ironvale","Shattergate","Voltmoor","Gritstone"
]

var regions: Array = []
var first_novice_pos: Vector2

@export var map_buttons: Array[TextureButton] = []  # drag them in order: map 1, map 2, …

func _ready():
	#randomize()              # only needed if you still want random branch‐counts/etc.
	#region_names.shuffle()   # ← remove this so names stay in fixed order
	var center = get_viewport_rect().size * 0.5
	# start with one Novice at the very center
	_generate_branch(center, 0, -90)

	for i in range(map_buttons.size()):
		# i goes 0…N-1, so map_id is i+1
		map_buttons[i].pressed.connect(Callable(self, "_on_map_pressed").bind(i+1))
	_update_map_highlights()
	_update_region_labels()

func _update_map_highlights() -> void:
	for i in range(map_buttons.size()):
		var btn    = map_buttons[i]
		var map_id = i + 1

		# only the “active” map is clickable
		btn.disabled = map_id != GameData.current_level

		if GameData.is_map_completed(map_id):
			# completed maps get a special tint
			btn.modulate = Color(1, 0.1, 0.1)
		elif map_id == GameData.current_level:
			# the one you can play now is normal
			btn.modulate = Color(1, 1, 1)
		else:
			# future/locked maps get dimmed
			btn.modulate = Color(0.3, 0.3, 0.3)

func _on_map_pressed(map_id: int) -> void:
	GameData.current_level = map_id
	get_tree().change_scene_to_file("res://Scenes/Main.tscn" % map_id)
				
# helper: returns the index of an existing region within 2×radius of `p`, or –1
func _find_region_at(p: Vector2) -> int:
	for i in range(regions.size()):
		if p.distance_to(regions[i]["pos"]) < region_radius * 2:
			return i
	return -1

func _generate_branch(pos: Vector2, depth: int, angle: float) -> void:
	# 1) either reuse or create this region
	var region_index = _find_region_at(pos)
	if region_index < 0:
		region_index = regions.size()
		_create_region_node(region_index, pos, depth)
	# otherwise we’ve “landed” on an existing node and we skip making a duplicate

	# 2) if we’re at max, stop here
	if depth >= max_depth:
		return

	# 3) spawn children as before
	var count = branches_per_node
	var spread = angle_spread / max(count - 1, 1)
	for i in range(count):
		var child_angle = angle - angle_spread * 0.5 + spread * i
		var length = branch_length
		var end_pos = pos + Vector2(cos(deg_to_rad(child_angle)), sin(deg_to_rad(child_angle))) * length

		# draw the line
		var line = Line2D.new()
		line.width = 4
		line.default_color = Color(0.25, 0.25, 0.25)
		line.points = [pos, end_pos]
		line.z_index = 0
		add_child(line)

		# recurse
		_generate_branch(end_pos, depth + 1, child_angle)

func _create_region_node(index: int, pos: Vector2, depth: int) -> void:
	# 1) compute tier, name & tint
	var tier       = clamp(depth + 1, 1, difficulty_tiers.size())
	var tier_name  = difficulty_tiers[tier]
	var hue        = float(tier) / difficulty_tiers.size()
	var base_tint  = Color.from_hsv(hue, 0.4, 0.8)

	# record first-novice position
	if tier == 1 and first_novice_pos == null:
		first_novice_pos = pos

	# 2) pick your texture for this tier
	var chosen_tex: Texture2D = null
	if tier - 1 < region_textures.size():
		chosen_tex = region_textures[tier - 1]

	# 3) create a TextureButton
	var btn: TextureButton = TextureButton.new()
	if chosen_tex:
		btn.texture_normal  = chosen_tex
		btn.texture_hover   = chosen_tex
		btn.texture_pressed = chosen_tex
		btn.size       = chosen_tex.get_size()
	else:
		btn.size       = Vector2(region_radius * 2, region_radius * 2)

	btn.position = pos - btn.size * 0.5
	btn.modulate      = base_tint
	add_child(btn)

	# 4) label underneath
	var lbl: Label = Label.new()
	lbl.text = "%s\n[%s]" % [
		region_names[index % region_names.size()],
		tier_name
	]
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	lbl.position        = pos + Vector2(0, region_radius + 4)
	if region_font:
		lbl.add_theme_font_override("font", region_font)
	add_child(lbl)

	# 5) hook up the pressed signal
	btn.pressed.connect(Callable(self, "_on_region_pressed").bind(index))

	# add hover signals:
	btn.connect("mouse_entered", Callable(self, "_on_region_hover").bind(index))
	btn.connect("mouse_exited",  Callable(self, "_on_region_unhover").bind(index))

	# store for later updates
	regions.append({
		"pos":       pos,
		"button":    btn,
		"label":     lbl,
		"base_tint": base_tint,
		"tier":      tier,    # <— add this
		"region_idx": index   # <— and this, so we know which name to print
	})

func _on_region_pressed(i: int) -> void:
	var tier := i + 1
	# only allow the region whose tier matches the current_level
	if tier != GameData.current_level:
		return

	emit_signal("region_selected", i, region_names[i])
	get_tree().change_scene_to_file("res://Scenes/Main.tscn")

func _on_region_hover(i: int) -> void:
	var entry = regions[i]
	# lighten the button on hover
	entry.button.modulate = entry.base_tint.lightened(2)

func _on_region_unhover(i: int) -> void:
	var entry = regions[i]
	# restore original tint
	entry.button.modulate = entry.base_tint

func _update_region_labels() -> void:
	for entry in regions:
		var lbl  : Label = entry["label"]
		var tier : int   = entry["tier"]
		if tier < GameData.current_level:
			# any tier *below* the current level is completed
			lbl.modulate = Color(1, 0, 0)    # red
		elif tier == GameData.current_level:
			# the one you’re on now
			lbl.modulate = Color(1, 1, 1)    # white (or whatever “active” color)
		else:
			# future tiers
			lbl.modulate = Color(0.5, 0.5, 0.5)
