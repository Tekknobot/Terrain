extends Node2D

@export var is_player: bool = true  
@export var unit_type: String = "Soldier"  
var health := 100
var max_health := 100
var xp := 0
var max_xp := 100
@export var movement_range := 2  
@export var attack_range := 3 

var has_moved := false


@onready var health_bar = $HealthUI
@onready var health_border = $HealthBorder
@onready var xp_bar = $XPUI

var tile_pos: Vector2i

signal movement_finished

@onready var EXPLOSION_SCENE = preload("res://Scenes/VFX/Explosion.tscn")  # Adjust the path

func _ready():
	update_z_index()
	update_health_bar()
	update_xp_bar()

func _process(delta):
	update_z_index()
	
func set_team(player_team: bool):
	is_player = player_team
	var sprite = get_node_or_null("AnimatedSprite2D")
	if sprite:
		if is_player:
			sprite.modulate = Color(1,1,1)
		else:
			sprite.modulate = Color(1, 110/255.0, 1)

func update_z_index():
	z_index = int(position.y)

			
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
	if tilemap and tilemap.all_units.has(self):
		var index = tilemap.all_units.find(self)

		# ⚠️ Adjust active_unit_index if needed
		if not is_player and index <= tilemap.active_unit_index:
			tilemap.active_unit_index -= 1

		tilemap.all_units.erase(self)

		# 💥 Play explosion effect (optional)
		var EXPLOSION_SCENE = preload("res://Scenes/VFX/Explosion.tscn")  # Adjust path
		var explosion = EXPLOSION_SCENE.instantiate()
		explosion.position = global_position + Vector2(0, -8)  # Optional offset
		tilemap.add_child(explosion)

	queue_free()

func _set_facing(from: Vector2i, to: Vector2i) -> void:
	var delta = to - from

	# Horizontal flip (left/right)
	if delta.x > 0:
		$AnimatedSprite2D.flip_h = true
	elif delta.x < 0:
		$AnimatedSprite2D.flip_h = false

	# Vertical flip (up/down)
	if delta.y > 0:
		$AnimatedSprite2D.flip_h = false   # moving down → normal
	elif delta.y < 0:
		$AnimatedSprite2D.flip_h = true    # moving up → flipped vertically

func flash_white():
	var sprite = $AnimatedSprite2D
	if sprite == null:
		return

	var original_color = sprite.modulate

	var flash_tween = create_tween()
	for i in range(6):
		flash_tween.tween_property(sprite, "modulate", Color(1,1,1), 0.05)
		flash_tween.tween_property(sprite, "modulate", Color(1,1,1,0.0), 0.05)
		flash_tween.tween_property(sprite, "modulate", Color(0,0,0), 0.05)
		flash_tween.tween_property(sprite, "modulate", original_color, 0.05)
