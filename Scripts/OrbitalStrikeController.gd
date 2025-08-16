extends Node2D

signal strike_finished   # <-- tell the world when we're done

@export var sfx_stream      : AudioStream
@export var flash_color     : Color  = Color(1,1,1,1)
@export var flash_time      : float  = 0.25
@export var laser_width     : float  = 1.0
@export var laser_color     : Color  = Color(1,0,0,1)
@export var laser_delay     : float  = 0.1
@export var laser_linger    : float  = 0.05
@export var laser_fade      : float  = 0.2
@export var laser_height    : float  = 400.0
@export var start_offset_x  : float  = 200.0

const ExplosionScene = preload("res://Scenes/VFX/Explosion.tscn")

func _ready() -> void:
	# SFX
	if sfx_stream:
		var sfx = AudioStreamPlayer2D.new()
		sfx.stream = sfx_stream
		add_child(sfx)
		sfx.play()

	# Full-screen flash
	var layer = CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	var flash = ColorRect.new()
	flash.color = flash_color
	flash.anchor_left = 0.0; flash.anchor_top = 0.0
	flash.anchor_right = 1.0; flash.anchor_bottom = 1.0
	layer.add_child(flash)
	var tw = create_tween()
	tw.tween_property(flash, "modulate:a", 0.0, flash_time)
	tw.tween_callback(Callable(layer, "queue_free"))

func _strike_all(is_player_team: bool) -> void:
	await _do_strike(is_player_team)
	emit_signal("strike_finished")   # ✅ ALWAYS fires
	# optional: self-cleanup
	queue_free()

# Internal so callers can just await strike_finished if they prefer
func _do_strike(is_player_team: bool) -> void:
	var vr    = get_viewport().get_visible_rect()
	var top_y = vr.position.y - laser_height

	# Snapshot enemies at cast time
	var targets: Array = []
	for z in get_tree().get_nodes_in_group("Units"):
		if z is Area2D and is_instance_valid(z) and z.has_method("take_damage") and z.is_player != is_player_team:
			targets.append(z)

	for unit in targets:
		var target_pos: Vector2
		if is_instance_valid(unit):
			target_pos = unit.global_position
		else:
			continue
		target_pos.y -= 8

		var sx = target_pos.x + randf_range(-start_offset_x, start_offset_x)
		var start_pos = Vector2(sx, top_y)

		var beam = Line2D.new()
		beam.width = laser_width
		beam.default_color = laser_color
		# Put the beam at the scene origin to keep local/global simple
		beam.global_position = Vector2.ZERO
		beam.add_point(start_pos)
		beam.add_point(target_pos)
		get_tree().get_current_scene().add_child(beam)

		var twb = get_tree().create_tween()
		twb.tween_interval(laser_linger)
		twb.tween_property(beam, "modulate:a", 0.0, laser_fade)
		twb.tween_callback(Callable(beam, "queue_free"))

		var exp = ExplosionScene.instantiate()
		exp.global_position = target_pos
		get_tree().get_current_scene().add_child(exp)

		if is_instance_valid(unit) and unit.is_player != is_player_team:
			unit.take_damage(40)

		await get_tree().create_timer(laser_delay).timeout
