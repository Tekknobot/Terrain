extends Node2D

signal region_selected(index, name)

@export var max_depth: int = 4
@export var branches_per_node: int = 3
@export var branch_length: float = 200.0
@export var length_variance: float = 0.5
@export var angle_spread: float = 90.0
@export var region_radius: float = 16.0
@export var region_font: Font

var difficulty_tiers: Dictionary = {
	1: "Novice", 2: "Apprentice", 3: "Adept", 4: "Expert",
	5: "Master", 6: "Grandmaster", 7: "Legendary", 8: "Mythic",
	9: "Transcendent", 10: "Celestial", 11: "Divine", 12: "Omnipotent"
}

@export var region_names: Array = [
	"Root", "Branchwood", "Silverleaf", "Ironforge", "Stormvale",
	"Suncrest", "Starfall", "Moonreach", "Frosthaven", "Emberfall",
	"Duskwood", "Brightwater", "Darkgrove", "Windhelm", "Ravenmoor",
	"Highspire", "Lowmarsh", "Goldcrest", "Shadowfen", "Crystalglade"
]

# Internal storage
var regions: Array = []
var first_novice_pos: Vector2
var follow_target: Vector2
var cam: Camera2D

func _ready():
	randomize()
	region_names.shuffle()
	var start_pos = get_viewport_rect().size * 0.5
	_generate_branch(start_pos, 0, 0, -90)
		
func _generate_branch(pos: Vector2, depth: int, idx: int, angle: float) -> void:
	var region_index = regions.size()
	_create_region_node(region_index, pos, depth)
	if depth >= max_depth:
		return
	var count = randi_range(1, branches_per_node)
	var spread = angle_spread / max(count - 1, 1)
	for i in range(count):
		var child_angle = angle - angle_spread * 0.5 + spread * i
		var length = branch_length * randf_range(1.0 - length_variance, 1.0 + length_variance)
		var rad = deg_to_rad(child_angle)
		var end_pos = pos + Vector2(cos(rad), sin(rad)) * length
		var line = Line2D.new()
		line.width = 4
		line.default_color = Color(0.25, 0.25, 0.25)
		line.points = [pos, end_pos]
		line.z_index = 0
		add_child(line)
		_generate_branch(end_pos, depth + 1, region_index * 10 + i, child_angle)

func _create_region_node(index: int, pos: Vector2, depth: int) -> void:
	var tier = clamp(depth + 1, 1, difficulty_tiers.size())
	var hue = float(tier) / difficulty_tiers.size()
	var fill = Color.from_hsv(hue, 0.4, 0.8)
	var outline_col = Color.from_hsv(hue, 0.8, 0.6)
	var tier_name = difficulty_tiers[tier]

	if tier == 1 and first_novice_pos == null:
		first_novice_pos = pos

	var circle = ColorRect.new()
	circle.color = fill
	circle.size = Vector2(region_radius * 2, region_radius * 2)
	circle.position = pos - Vector2(region_radius, region_radius)
	circle.z_index = 1
	# ← add this so the ColorRect does NOT block mouse events
	circle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(circle)

	var area = Area2D.new()
	area.z_index = 1
	area.position = pos
	var col = CollisionShape2D.new()
	var shape = CircleShape2D.new()
	shape.radius = region_radius
	col.shape = shape
	area.add_child(col)
	add_child(area)

	var lbl = Label.new()
	lbl.text = "%s\n[%s]" % [region_names[index % region_names.size()], tier_name]
	lbl.position = pos + Vector2(0, region_radius + 4)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.z_index = 2
	if region_font:
		lbl.add_theme_font_override("font", region_font)
	add_child(lbl)

	area.connect("mouse_entered", Callable(self, "_on_hover").bind(index))
	area.connect("mouse_exited", Callable(self, "_on_unhover").bind(index))
	area.connect("input_event", Callable(self, "_on_click").bind(index))

	regions.append({"pos":pos, "circle":circle, "label":lbl, "area":area})

func _on_hover(i: int) -> void:
	var reg = regions[i]
	reg.circle.modulate = reg.circle.color.lightened(0.3)

func _on_unhover(i: int) -> void:
	var reg = regions[i]
	reg.circle.modulate = reg.circle.color

func _on_click(idx: int, _viewport, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		emit_signal("region_selected", idx, region_names[idx % region_names.size()])
		follow_target = regions[idx]["pos"]    # ← start lerping toward this
