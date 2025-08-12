extends Node2D

signal region_selected(index, name)

# ───────── Visual config ─────────
@export var region_font: Font
@export var region_textures: Array[Texture2D] = []   # one per tier (Novice..Grandmaster..)
@export var region_radius: float = 18.0

# Land / layout config
@export var island_count: int = 4
@export var nodes_per_island_min: int = 5
@export var nodes_per_island_max: int = 8
@export var coast_points: int = 36
@export var island_base_radius: float = 260.0
@export var island_radius_jitter: float = 70.0
@export var coast_noise_strength: float = 0.22
@export var min_node_spacing: float = 80.0
@export var bridge_extra_links: int = 1

# Colors
@export var land_fill: Color = Color(0.10, 0.12, 0.14, 1.0)
@export var coast_line: Color = Color(0.05, 0.05, 0.05, 1.0)
@export var road_color: Color = Color(0.28, 0.28, 0.28, 1.0)

# ── Pan/drag state
var _dragging := false
var _drag_mouse_start := Vector2.ZERO
var _drag_node_start  := Vector2.ZERO

# Difficulty names
var difficulty_tiers := {
	1: "Novice", 2: "Apprentice", 3: "Adept",
	4: "Expert", 5: "Master", 6: "Grandmaster",
	7: "Legendary", 8: "Mythic", 9: "Transcendent",
	10: "Celestial", 11: "Divine", 12: "Omnipotent"
}

# Region name bank
@export var region_names: Array = [
	"Ironhold","Gearfall","Steelforge","Rusthaven","Cinderwall",
	"Forgekeep","Pulsegate","Hammerfall","Blastmoor","Magnetar",
	"Titanreach","Axlepoint","Vulcannon","Boltspire","Mecharis",
	"Lockridge","Quakefield","Junktown","Arcforge","ZeroCore",
	"Crankton","Ironvale","Shattergate","Voltmoor","Gritstone"
]

# Internals
var islands: Array = []     # [{poly: PackedVector2Array, center: Vector2, nodes: [region_indices]}]
var regions: Array = []     # [{pos, button, label, base_tint, tier, region_idx, parents: [], name}]
var rng := RandomNumberGenerator.new()

# ── Tier shaping
const DEAD_END_CHANCE := 0.35   # higher → more cul-de-sacs
const MAX_TIER := 6             # cap at Grandmaster

# Adjacency for graph operations
var _adj: Dictionary = {}       # node_id -> Array[int]

# Tier colors from coolest (Novice) to warmest (Grandmaster)
var tier_colors := {
	1: Color(0.0, 0.4, 1.0),    # vivid blue
	2: Color(0.0, 1.0, 1.0),    # bright cyan
	3: Color(0.0, 1.0, 0.0),    # bright green
	4: Color(1.0, 1.0, 0.0),    # bright yellow
	5: Color(1.0, 0.5, 0.0),    # bright orange
	6: Color(1.0, 0.0, 0.0)     # pure red
}

@export var deterministic: bool = true
@export var fixed_seed: int = 123456   # change this to get a different but repeatable map

@export var hover_scale: float = 1.5   # how big on hover
@export var hover_time: float = 0.12    # seconds for tween

var _hover_tweens := {}   # btn_id -> SceneTreeTween

func _ready():
	# Create a session seed once, then reuse it for the rest of the run.
	if GameData.overworld_seed == 0:
		var tmp := RandomNumberGenerator.new()
		tmp.randomize()                      # truly random just once per app launch
		GameData.overworld_seed = tmp.randi()
	
	rng.seed = GameData.overworld_seed       # always use the same session seed

	_generate_world()
	_update_region_interactivity()
	_update_region_labels()

func _input(event: InputEvent) -> void:
	# Drag with Right or Middle mouse (prevents fighting with left-click buttons)
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging = mb.pressed
			_drag_mouse_start = mb.position
			_drag_node_start  = position
			return

	if _dragging and event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		position += mm.relative

func _make_circle_texture(radius: int, color: Color) -> Texture2D:
	var size := radius * 2
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0,0,0,0))
	var r := float(radius) - 0.5
	var r2 := r * r
	for y in range(size):
		for x in range(size):
			var dx := x - radius + 0.5
			var dy := y - radius + 0.5
			var d2 := dx*dx + dy*dy
			if d2 <= r2:
				img.set_pixel(x, y, color)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

# ─────────────────────────────────────────────────────────────────────────────
# Top-level generation
# ─────────────────────────────────────────────────────────────────────────────
func _generate_world() -> void:
	# Clear any prior children if regenerating
	for c in get_children():
		remove_child(c); c.queue_free()
	islands.clear()
	regions.clear()
	_adj.clear()

	var vp = get_viewport_rect().size
	var centers := _island_centers_grid(vp, island_count)

	# Create islands
	for c in centers:
		var poly := _make_island_polygon(c, island_base_radius + rng.randf_range(-island_radius_jitter, island_radius_jitter))
		_draw_island(poly)
		islands.append({ "poly": poly, "center": c, "nodes": [] })

	# Scatter region nodes on land
	var name_idx := 0
	for i in range(islands.size()):
		var ncount := rng.randi_range(nodes_per_island_min, nodes_per_island_max)
		for j in range(ncount):
			var p = _random_point_in_polygon_nonoverlap(islands[i]["poly"], min_node_spacing, 128)
			if p == null:
				continue
			var region_index := regions.size()
			_create_region_node(region_index, p, 0, -1, name_idx) # depth stub unused
			islands[i]["nodes"].append(region_index)
			name_idx += 1

	# Init adjacency buckets for all nodes
	for i in range(regions.size()):
		_adj[i] = []

	# Build roads: per-island MST + extra local edges
	for isl in islands:
		_connect_island_nodes(isl["nodes"])

	# Bridges between islands (closest pairs)
	_connect_islands()

	# Assign tiers with a clean backbone (Novice → … → 6) + cul-de-sacs
	var spine := _assign_tiers_backbone()

	# Redraw region visuals (colors/labels) now that tiers are known
	for i in range(regions.size()):
		_update_region_visuals(i)

	# Optional: subtle highlight for the main spine
	for n in spine:
		if n >= 0 and n < regions.size():
			regions[n]["button"].modulate = regions[n]["button"].modulate.lightened(0.12)

# ─────────────────────────────────────────────────────────────────────────────
# Island placement & polygons
# ─────────────────────────────────────────────────────────────────────────────
func _island_centers_grid(vp_size: Vector2, count: int) -> Array:
	var cols := int(ceil(sqrt(count)))
	var rows := int(ceil(float(count) / cols))
	var pad := Vector2(260, 220)
	var cell := Vector2(
		max((vp_size.x - pad.x * 2) / max(cols, 1), island_base_radius * 1.5),
		max((vp_size.y - pad.y * 2) / max(rows, 1), island_base_radius * 1.3)
	)
	var centers: Array = []
	var k := 0
	for r in range(rows):
		for c in range(cols):
			if k >= count:
				break
			var base := Vector2(pad.x + cell.x * (c + 0.5), pad.y + cell.y * (r + 0.5))
			base += Vector2(
				rng.randf_range(-cell.x*0.18, cell.x*0.18),
				rng.randf_range(-cell.y*0.18, cell.y*0.18)
			)
			centers.append(base)
			k += 1
	return centers

func _make_island_polygon(center: Vector2, radius: float) -> PackedVector2Array:
	var pts: Array[Vector2] = []
	for i in range(coast_points):
		var t := float(i) / float(coast_points)
		var ang := t * TAU
		var ring = 1.0 + coast_noise_strength * sin(3.0 * ang + rng.randf_range(-0.6, 0.6)) \
			+ coast_noise_strength * 0.5 * sin(5.0 * ang + rng.randf_range(-0.6, 0.6))
		var r = radius * clamp(ring, 0.6, 1.6)
		var p = center + Vector2(cos(ang), sin(ang)) * r
		pts.append(p)
	return PackedVector2Array(pts)

func _draw_island(poly: PackedVector2Array) -> void:
	var land := Polygon2D.new()
	land.polygon = poly
	land.color = land_fill
	add_child(land)

	var coast := Line2D.new()
	coast.default_color = coast_line
	coast.width = 6
	coast.closed = true
	coast.points = poly
	coast.z_index = 1
	add_child(coast)

# ─────────────────────────────────────────────────────────────────────────────
# Region nodes
# ─────────────────────────────────────────────────────────────────────────────
func _create_region_node(index: int, pos: Vector2, _depth_stub: int, parent_index: int, name_idx: int) -> void:
	var tier := 1
	var tier_name = difficulty_tiers[tier]
	var hue := float(tier) / difficulty_tiers.size()
	var base_tint := Color.from_hsv(hue, 0.35, 0.9)

	var circle_tex := _make_circle_texture(int(region_radius), Color.WHITE) # white, tint via modulate

	var btn := TextureButton.new()
	btn.texture_normal  = circle_tex
	btn.texture_hover   = circle_tex
	btn.texture_pressed = circle_tex
	btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	btn.size = Vector2(region_radius * 2, region_radius * 2)

	# Center pivot for scaling animations
	btn.pivot_offset = btn.size * 0.5
	btn.scale = Vector2.ONE
	
	btn.position = pos - btn.size * 0.5
	btn.modulate = base_tint
	btn.z_index = 5
	# Important: allow RMB/MMB to pass through for panning
	btn.mouse_filter = Control.MOUSE_FILTER_PASS
	btn.focus_mode = Control.FOCUS_NONE
	add_child(btn)

	var name = region_names[name_idx % region_names.size()]
	var lbl := Label.new()
	lbl.text = name
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	lbl.position = pos + Vector2(0, region_radius + 8)
	if region_font:
		lbl.add_theme_font_override("font", region_font)
	lbl.z_index = 6
	add_child(lbl)

	btn.pressed.connect(Callable(self, "_on_region_pressed").bind(index))
	btn.connect("mouse_entered", Callable(self, "_on_region_hover").bind(index))
	btn.connect("mouse_exited",  Callable(self, "_on_region_unhover").bind(index))

	var parents := []
	if parent_index >= 0:
		parents.append(parent_index)

	regions.append({
		"pos": pos,
		"button": btn,
		"label": lbl,
		"base_tint": base_tint,
		"tier": tier,
		"region_idx": index,
		"parents": parents,
		"name": name,
	})

func _update_region_visuals(i: int) -> void:
	var e = regions[i]
	var tier: int = e["tier"]
	var tier_name: String = difficulty_tiers.get(tier, "???")

	var tint: Color
	if tier_colors.has(tier):
		tint = tier_colors[tier]
	else:
		tint = Color.WHITE

	e["button"].modulate = tint

	var lbl: Label = e["label"]
	lbl.text = e["name"]

# ─────────────────────────────────────────────────────────────────────────────
# Roads & bridges
# ─────────────────────────────────────────────────────────────────────────────
func _connect_island_nodes(node_indices: Array) -> void:
	if node_indices.size() <= 1:
		return

	# Build a local MST (Prim’s) for island roads
	var in_tree: Array = []
	var remaining := node_indices.duplicate()
	in_tree.append(remaining.pop_back())

	while remaining.size() > 0:
		var best_u := -1
		var best_v := -1
		var best_d := INF
		for u in in_tree:
			for v in remaining:
				var d = regions[u]["pos"].distance_to(regions[v]["pos"])
				if d < best_d:
					best_d = d; best_u = u; best_v = v
		_add_edge(best_u, best_v)
		in_tree.append(best_v)
		remaining.erase(best_v)

	# Add a couple short extra links for loops
	var extras = min(2, node_indices.size() / 3)
	for k in range(extras):
		var a = node_indices[rng.randi_range(0, node_indices.size()-1)]
		var b := _nearest_different(a, node_indices)
		if b >= 0:
			_add_edge(a, b)

func _connect_islands() -> void:
	# Connect each island to its nearest neighbor
	for i in range(islands.size()):
		var best_j := -1
		var best_dist := INF
		var ai = islands[i]
		var ai_nodes: Array = ai["nodes"]
		if ai_nodes.is_empty():
			continue

		for j in range(islands.size()):
			if j == i:
				continue
			var aj = islands[j]
			var pair = _closest_node_pair(ai_nodes, aj["nodes"])
			if pair == null:
				continue
			var d = regions[pair[0]]["pos"].distance_to(regions[pair[1]]["pos"])
			if d < best_dist:
				best_dist = d; best_j = j
		if best_j >= 0:
			var pair2 = _closest_node_pair(ai_nodes, islands[best_j]["nodes"])
			if pair2 != null:
				_add_edge(pair2[0], pair2[1])

	# optional extra random bridges
	for n in range(bridge_extra_links):
		var i1 := rng.randi_range(0, islands.size()-1)
		var i2 := (i1 + rng.randi_range(1, islands.size()-1)) % islands.size()
		var pair = _closest_node_pair(islands[i1]["nodes"], islands[i2]["nodes"])
		if pair != null:
			_add_edge(pair[0], pair[1])

func _closest_node_pair(a: Array, b: Array) -> Variant:
	if a.is_empty() or b.is_empty():
		return null
	var best := [a[0], b[0]]
	var dmin := INF
	for i in a:
		for j in b:
			var d = regions[i]["pos"].distance_to(regions[j]["pos"])
			if d < dmin:
				dmin = d
				best = [i, j]
	return best

func _nearest_different(a: int, pool: Array) -> int:
	var pa = regions[a]["pos"]
	var best := -1
	var dmin := INF
	for i in pool:
		if i == a:
			continue
		var d = pa.distance_to(regions[i]["pos"])
		if d < dmin:
			dmin = d; best = i
	return best

func _add_edge(u: int, v: int) -> void:
	if u == v:
		return

	# If adjacency already exists, do nothing (prevents duplicate roads)
	if _adj.has(u) and _adj[u].has(v):
		return

	# Store parent link (non-linear unlocks keep both directions)
	if not regions[v]["parents"].has(u):
		regions[v]["parents"].append(u)
	if not regions[u]["parents"].has(v):
		regions[u]["parents"].append(v)

	# Maintain adjacency
	if not _adj.has(u):
		_adj[u] = []
	if not _adj.has(v):
		_adj[v] = []
	_adj[u].append(v)
	_adj[v].append(u)

	# Draw the road once
	_draw_road(regions[u]["pos"], regions[v]["pos"])

func _draw_road(a: Vector2, b: Vector2) -> void:
	var mid := (a + b) * 0.5
	var dir := (b - a)
	var perp := Vector2(-dir.y, dir.x).normalized()
	var bulge = 0.0

	var p0 := a
	var p1 = mid + perp * bulge
	var p2 := b

	var pts: Array[Vector2] = []
	var steps := 18
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var q0 := p0.lerp(p1, t)
		var q1 = p1.lerp(p2, t)
		var p  := q0.lerp(q1, t)
		pts.append(p)

	var line := Line2D.new()
	line.width = 6
	line.default_color = road_color
	line.points = pts
	line.z_index = 2
	add_child(line)

# ─────────────────────────────────────────────────────────────────────────────
# Tier assignment (Backbone + cul-de-sacs)
# ─────────────────────────────────────────────────────────────────────────────
func _assign_tiers_backbone() -> Array:
	if regions.is_empty():
		return []

	# 1) HQ (closest to viewport center)
	var center := get_viewport_rect().size * 0.5
	var hq := 0
	var dmin := INF
	for i in range(regions.size()):
		var d = regions[i]["pos"].distance_to(center)
		if d < dmin:
			dmin = d; hq = i

	# 2) Long-ish path via two BFS sweeps
	var a := _farthest_from(hq)
	var b := _farthest_from(a)
	var path_hq_a := _reconstruct_path(hq, a)
	var path_hq_b := _reconstruct_path(hq, b)

	# 3) Choose backbone starting at HQ up to 6 nodes
	var backbone: Array = []
	if path_hq_a.size() >= MAX_TIER:
		backbone = path_hq_a.slice(0, MAX_TIER)
	elif path_hq_b.size() >= MAX_TIER:
		backbone = path_hq_b.slice(0, MAX_TIER)
	else:
		if path_hq_a.size() > path_hq_b.size():
			backbone = path_hq_a
		else:
			backbone = path_hq_b
		while backbone.size() < MAX_TIER:
			var tail = backbone.back()
			var extended := false
			for n in _adj.get(tail, []):
				if not backbone.has(n):
					backbone.append(n)
					extended = true
					break
			if not extended:
				break

	# 4) Assign tiers along the backbone: 1..6
	var assigned := {}
	for idx in range(backbone.size()):
		var node = backbone[idx]
		var tier = clamp(1 + idx, 1, MAX_TIER)
		regions[node]["tier"] = tier
		assigned[node] = true

	# 5) Grow side branches outward, creating cul-de-sacs
	var q: Array = []
	for node in backbone:
		q.append(node)

	while not q.is_empty():
		var u = q.pop_front()
		var t: int = regions[u]["tier"]

		for v in _adj.get(u, []):
			if assigned.has(v):
				continue
			var next_tier = min(t + 1, MAX_TIER)
			regions[v]["tier"] = next_tier
			assigned[v] = true
			if next_tier < MAX_TIER and rng.randf() > DEAD_END_CHANCE:
				q.append(v)
			# else dead-end: stop

	# 6) Any isolated nodes not touched: set to tier 2
	for i in range(regions.size()):
		if not assigned.has(i):
			regions[i]["tier"] = 2

	return backbone

func _farthest_from(src: int) -> int:
	var dist := {}
	for i in range(regions.size()):
		dist[i] = 999999
	dist[src] = 0
	var q := [src]
	while not q.is_empty():
		var u = q.pop_front()
		for v in _adj.get(u, []):
			if dist[v] > dist[u] + 1:
				dist[v] = dist[u] + 1
				q.append(v)
	var best := src
	var best_d := -1
	for k in dist.keys():
		if dist[k] > best_d and dist[k] < 999999:
			best_d = dist[k]
			best = k
	return best

func _reconstruct_path(src: int, dst: int) -> Array:
	# BFS to capture parents
	var parent := {}
	for i in range(regions.size()):
		parent[i] = -2  # unseen
	var q := [src]
	parent[src] = -1
	while not q.is_empty():
		var u = q.pop_front()
		if u == dst:
			break
		for v in _adj.get(u, []):
			if parent[v] == -2:
				parent[v] = u
				q.append(v)
	# Rebuild path
	var path: Array = []
	var cur := dst
	if parent[cur] == -2:
		return [src]  # disconnected; fall back
	while cur != -1:
		path.append(cur)
		cur = parent[cur]
	path.reverse()
	return path

# ─────────────────────────────────────────────────────────────────────────────
# Interactivity & labels (non-linear unlocks)
# ─────────────────────────────────────────────────────────────────────────────
func _update_region_interactivity() -> void:
	for i in range(regions.size()):
		var e = regions[i]
		var completed := GameData.is_region_completed(i)
		var unlocked  := GameData.is_region_unlocked(i, e["tier"], e["parents"])

		# Completed regions are never selectable again.
		e["button"].disabled = completed or (not unlocked)

func _update_region_labels() -> void:
	for i in range(regions.size()):
		var e = regions[i]
		var lbl: Label = e["label"]
		var t: int = e["tier"]
		var completed := GameData.is_region_completed(i)
		var unlocked  := GameData.is_region_unlocked(i, t, e["parents"])

		if completed:
			lbl.modulate = Color(1, 0.2, 0.2)
		elif unlocked:
			lbl.modulate = Color(1, 1, 1)
		else:
			lbl.modulate = Color(0.5, 0.5, 0.5)

# ─────────────────────────────────────────────────────────────────────────────
# Input
# ─────────────────────────────────────────────────────────────────────────────
func _on_region_pressed(i: int) -> void:
	var e = regions[i]
	var tier: int = e["tier"]

	# Block if completed or not unlocked.
	if GameData.is_region_completed(i):
		return
	if not GameData.is_region_unlocked(i, tier, e["parents"]):
		return

	GameData.last_region_index = i
	GameData.last_region_tier  = tier
	emit_signal("region_selected", i, e["name"])
	get_tree().change_scene_to_file("res://Scenes/Main.tscn")

func _on_region_hover(i: int) -> void:
	var e = regions[i]
	# don’t animate disabled/completed nodes
	if e["button"].disabled or GameData.is_region_completed(i):
		return
	_tween_button_scale(e["button"], hover_scale)

func _on_region_unhover(i: int) -> void:
	var e = regions[i]
	_tween_button_scale(e["button"], 1.0)


# ─────────────────────────────────────────────────────────────────────────────
# Geometry helpers
# ─────────────────────────────────────────────────────────────────────────────
func _random_point_in_polygon_nonoverlap(poly: PackedVector2Array, spacing: float, attempts: int) -> Variant:
	for _i in range(attempts):
		var bb := _poly_aabb(poly)
		var p := Vector2(
			rng.randf_range(bb.position.x, bb.position.x + bb.size.x),
			rng.randf_range(bb.position.y, bb.position.y + bb.size.y)
		)
		if not _point_in_polygon(p, poly):
			continue
		var ok := true
		for r in regions:
			if p.distance_to(r["pos"]) < spacing:
				ok = false
				break
		if ok:
			return p
	return null

func _poly_aabb(poly: PackedVector2Array) -> Rect2:
	var minx := INF; var miny := INF; var maxx := -INF; var maxy := -INF
	for v in poly:
		minx = min(minx, v.x); miny = min(miny, v.y)
		maxx = max(maxx, v.x); maxy = max(maxy, v.y)
	return Rect2(Vector2(minx, miny), Vector2(maxx-minx, maxy-miny))

func _point_in_polygon(p: Vector2, poly: PackedVector2Array) -> bool:
	var inside := false
	var j := poly.size() - 1
	for i in range(poly.size()):
		var pi := poly[i]; var pj := poly[j]
		if ((pi.y > p.y) != (pj.y > p.y)) and (p.x < (pj.x - pi.x) * (p.y - pi.y) / (pj.y - pi.y + 0.00001) + pi.x):
			inside = not inside
		j = i
	return inside

func _tween_button_scale(btn: TextureButton, target: float) -> void:
	var id := btn.get_instance_id()
	if _hover_tweens.has(id):
		var old = _hover_tweens[id]
		if old and old.is_valid():
			old.kill()
	var tw := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_hover_tweens[id] = tw
	tw.tween_property(btn, "scale", Vector2(target, target), hover_time)
