extends Node2D

@export var line_color: Color = Color(0.8, 0.9, 1.0, 1.0)
@export var line_width: float = 1.0
@export var segments: int = 8
@export var max_offset: float = 8.0
@export var start_offset: float = 128.0
@export var sfx_stream = preload("res://Audio/SFX/loud-thunder-192165.mp3")

@export var flash_time: float = 1.0

const ExplosionScene = preload("res://Scenes/VFX/Explosion.tscn")

var _line: Line2D
var _sfx_player: AudioStreamPlayer2D

@export var bolt_line: Line2D
@export var joint_particle_scene: PackedScene = preload("res://Scenes/VFX/Lightning_Joint.tscn")

func _ready() -> void:
	z_index = 9999
	z_as_relative = false

	_line = Line2D.new()
	_line.width = line_width
	_line.default_color = line_color
	_line.z_index = 9999
	_line.z_as_relative = false
	add_child(_line)

	if sfx_stream:
		_sfx_player = AudioStreamPlayer2D.new()
		_sfx_player.stream = sfx_stream
		_sfx_player.attenuation = 0.0
		add_child(_sfx_player)

# 🔥 Updated method: strike only the provided target_unit
func fire(target_unit: Area2D, damage: int, is_player_team: bool) -> void:
	var target_pos = target_unit.global_position
	target_pos.y -= 8

	if _sfx_player:
		remove_child(_sfx_player)
		get_tree().get_current_scene().add_child(_sfx_player)
		_sfx_player.global_position = target_pos
		_sfx_player.play()

	var vr = get_viewport().get_visible_rect()
	var start_pos = Vector2(target_pos.x, vr.position.y - start_offset)
	_line.clear_points()
		
	for i in range(segments + 1):
		var t = float(i) / segments
		var p = start_pos.lerp(target_pos, t)
		if i > 0 and i < segments:
			p.x += randf_range(-max_offset, max_offset)
		_line.add_point(to_local(p))

		var spark = joint_particle_scene.instantiate() as CPUParticles2D
		get_tree().get_current_scene().add_child(spark)
		spark.global_position = p
		spark.z_index = 9999  # 🔥 Force above other objects
		spark.z_as_relative = false
		spark.emitting = true

	# 🔒 Only strike the specified unit if it is a valid target
	if target_unit and target_unit.is_player != is_player_team:
		target_unit.take_damage(damage)

		var exp = ExplosionScene.instantiate()
		exp.global_position = target_unit.global_position
		get_tree().get_current_scene().add_child(exp)

	var steps = 8
	for s in range(steps):
		_line.default_color.a = lerp(1.0, 0.0, float(s + 1) / steps)
		await get_tree().create_timer(flash_time / steps).timeout

	queue_free()
