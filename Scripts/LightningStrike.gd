# res://Scripts/LightningStrike.gd
extends Node2D

@export var line_color:     Color   = Color(0.8,0.9,1.0,1.0)
@export var line_width:     float   = 1.0
@export var segments:       int     = 24       # more = smoother bolt
@export var max_offset:     float   = 8.0     # jaggedness per segment
@export var start_offset:   float   = 400.0    # how far above viewport to begin
@export var sfx_stream = preload("res://Audio/SFX/loud-thunder-192165.mp3")

@export var flash_time:     float   = 1      # seconds to fade out

const ExplosionScene = preload("res://Scenes/VFX/Explosion.tscn")

var _line:       Line2D
var _sfx_player: AudioStreamPlayer2D

@export var bolt_line: Line2D              # your existing line2D for drawing
@export var joint_particle_scene: PackedScene = preload("res://Scenes/VFX/Lightning_Joint.tscn")

func _ready() -> void:
	# 1) Make the Line2D
	_line = Line2D.new()
	_line.width = line_width
	_line.default_color = line_color
	add_child(_line)

	# 2) Prepare the SFX player (but don't play until fire())
	if sfx_stream:
		_sfx_player = AudioStreamPlayer2D.new()
		_sfx_player.stream = sfx_stream
		_sfx_player.attenuation = 0.0
		add_child(_sfx_player)


func fire(target_pos: Vector2, damage: int) -> void:
	# Offset the strike so it appears just above ground
	target_pos.y -= 8

	# --- Audio: detach so it survives this node’s queue_free() ---
	if _sfx_player:
		remove_child(_sfx_player)
		get_tree().get_current_scene().add_child(_sfx_player)
		_sfx_player.global_position = target_pos
		_sfx_player.play()

	# --- Draw bolt over time and spawn spark at each joint ---
	var vr = get_viewport().get_visible_rect()
	var start_pos = Vector2(target_pos.x, vr.position.y - start_offset)
	_line.clear_points()

	for i in range(segments + 1):
		var t = float(i) / segments
		var p = start_pos.lerp(target_pos, t)
		if i > 0 and i < segments:
			p.x += randf_range(-max_offset, max_offset)

		_line.add_point(to_local(p))

		# ─── new: particle at this joint ───
		var spark = joint_particle_scene.instantiate() as CPUParticles2D
		get_tree().get_current_scene().add_child(spark)
		spark.global_position = p
		spark.emitting = true

	for z in get_tree().get_nodes_in_group("Units"):
		if z is Area2D and z.global_position.distance_to(target_pos) < 16 and !z.is_player:
			z.take_damage(damage)
			# --- Explosion & damage ---
			var exp = ExplosionScene.instantiate()
			exp.global_position = target_pos
			get_tree().get_current_scene().add_child(exp)
			
	# --- Fade the bolt out over flash_time ---
	var steps = 8
	for s in range(steps):
		_line.default_color.a = lerp(1.0, 0.0, float(s + 1) / steps)
		await get_tree().create_timer(flash_time / steps).timeout

	queue_free()
