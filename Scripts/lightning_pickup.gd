# lightning_pickup.gd
extends Area2D

@export var lightning_scene := preload("res://Prefabs/LightningController.tscn")

@export var wiggle_amplitude: float = 5.0
@export var wiggle_speed: float = 2.5
@export var rotate_speed: float = 2.0

var base_y: float

func _ready():
	monitoring = true
	connect("area_entered", Callable(self, "_on_area_entered"))
	base_y = position.y
	set_process(true)

func _process(delta):
	var t = Time.get_ticks_msec() / 1000.0
	position.y = base_y + sin(t * wiggle_speed) * wiggle_amplitude
	rotation += rotate_speed * delta

func _on_area_entered(area):
	if area.is_in_group("Units"):
		print("⚡ Lightning pickup collected!")
		_trigger_lightning_storm(area.is_player)  # ← pass the team info

		if $AudioStreamPlayer2D:
			$AudioStreamPlayer2D.play()
			await $AudioStreamPlayer2D.finished

		queue_free()

func _trigger_lightning_storm(is_player_team: bool):
	if not lightning_scene:
		push_error("❗ LightningController scene not found!")
		return

	var lightning = lightning_scene.instantiate()
	get_tree().get_current_scene().add_child(lightning)
	lightning.start(3.0, 1.0, 1, 15, is_player_team)
	lightning.z_index = 9999
