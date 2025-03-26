extends Node2D

@export var is_player: bool = true  
@export var unit_type: String = "Soldier"  
var health := 100
var max_health := 100
var xp := 0
var max_xp := 100
@export var movement_range := 2  
@export var attack_range := 3 

var tile_pos: Vector2i

signal movement_finished

@onready var health_bar = $HealthUI
@onready var xp_bar = $XPUI

func _ready():
	update_z_index()
	update_health_bar()
	update_xp_bar()

func update_z_index():
	z_index = int(position.y)

### TURN MANAGEMENT ###
func start_turn():
	if is_player:
		# Wait for player input — call on_player_done() when finished
		return
	perform_ai_action()

func on_player_done():
	TurnManager.unit_finished_action(self)

func perform_ai_action():
	var tilemap = get_tree().get_current_scene().get_node("TileMap")
	var target = TurnManager.find_closest_enemy(self)
	if target == null:
		return TurnManager.unit_finished_action(self)

	# Unblock for pathfinding
	tilemap.astar.set_point_solid(tile_pos, false)
	tilemap.astar.set_point_solid(target.tile_pos, false)
	var path = tilemap.astar.get_point_path(tile_pos, target.tile_pos)
	tilemap.astar.set_point_solid(tile_pos, true)
	tilemap.astar.set_point_solid(target.tile_pos, true)

	if path.is_empty():
		return TurnManager.unit_finished_action(self)

	# Move step-by-step
	for i in range(1, min(path.size(), movement_range + 1)):
		await move_to_async(path[i])

	if tile_pos.distance_to(target.tile_pos) <= attack_range:
		attack(target)

	TurnManager.unit_finished_action(self)

func move_to_async(dest: Vector2i) -> void:
	var tilemap = get_tree().get_current_scene().get_node("TileMap")
	var sprite = $AnimatedSprite2D

	var start_pos = global_position
	var end_pos = tilemap.to_global(tilemap.map_to_local(dest))
	tile_pos = dest

	# Play move animation
	if sprite:
		sprite.play("move")

	var distance = start_pos.distance_to(end_pos)
	var duration = distance / 75.0

	var tween = create_tween()
	tween.tween_property(self, "global_position", end_pos, duration)
	await tween.finished

	# Restore default (idle) animation
	if sprite:
		sprite.play("default")

func move_to(dest: Vector2i):
	var tilemap = get_tree().get_current_scene().get_node("TileMap")
	tile_pos = dest
	global_position = tilemap.to_global(tilemap.map_to_local(dest))
	emit_signal("movement_finished")

func attack(target):
	var damage = 25
	target.take_damage(damage)

	# Pushback
	var dir = (target.tile_pos - tile_pos).sign()
	var push = target.tile_pos + dir
	var tilemap = get_tree().get_current_scene().get_node("TileMap")
	if tilemap.is_within_bounds(push) and not tilemap.is_tile_occupied(push) and tilemap._is_tile_walkable(push):
		target.tile_pos = push
		target.global_position = tilemap.to_global(tilemap.map_to_local(push))

	target.flash_white()
	if target.health == 0:
		gain_xp(50)

### HEALTH & XP ###
func take_damage(amount: int):
	health = max(health - amount, 0)
	update_health_bar()
	if health == 0:
		die()

func gain_xp(amount: int):
	xp = min(xp + amount, max_xp)
	update_xp_bar()

func update_health_bar():
	if health_bar != null:
		health_bar.value = float(health) / max_health * 100

func update_xp_bar():
	if xp_bar != null:
		xp_bar.value = float(xp) / max_xp * 100

func die():
	var tilemap = get_tree().get_current_scene().get_node("TileMap")
	tilemap.all_units.erase(self)
	var explosion = preload("res://Scenes/VFX/Explosion.tscn").instantiate()
	explosion.position = global_position + Vector2(0, -8)
	tilemap.add_child(explosion)
	queue_free()

func flash_white():
	var sprite = $AnimatedSprite2D
	if sprite == null:
		return
	var original = sprite.modulate
	var t = create_tween()
	for i in range(6):
		t.tween_property(sprite, "modulate", Color(1,1,1), 0.05)
		t.tween_property(sprite, "modulate", original, 0.05)

func set_team(player_team: bool) -> void:
	is_player = player_team
	var sprite = get_node_or_null("AnimatedSprite2D")
	if sprite:
		if is_player:
			sprite.modulate = Color(1, 1, 1)    # normal tint for player
		else:
			sprite.modulate = Color(1, 0.43, 1)  # tinted purple for enemy
