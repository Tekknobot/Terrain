extends Area2D

@export var orbital_scene := preload("res://Scenes/VFX/orbital_strike_controller.tscn")

# Wiggle & rotate parameters
@export var wiggle_amplitude: float = 5.0
@export var wiggle_speed: float = 2.5
@export var rotate_speed: float = 2.0

var base_y: float

func _ready():
	monitoring = true
	connect("area_entered", Callable(self, "_on_area_entered"))
	base_y = position.y
	set_process(true)

func _process(delta: float) -> void:
	var t = Time.get_ticks_msec() / 1000.0
	position.y = base_y + sin(t * wiggle_speed) * wiggle_amplitude
	rotation += rotate_speed * delta

func _on_area_entered(area: Area2D) -> void:
	if area.is_in_group("Units"):
		print("🚀 Orbital strike pickup collected!")
		_trigger_orbital_strike(area.is_player)

		if $AudioStreamPlayer2D:
			$AudioStreamPlayer2D.play()
			await $AudioStreamPlayer2D.finished

		queue_free()

func _trigger_orbital_strike(is_player_team: bool) -> void:
	if not orbital_scene:
		push_error("❗ OrbitalStrikeController scene not found!")
		return

	var orbital = orbital_scene.instantiate()
	get_tree().get_current_scene().add_child(orbital)
	orbital._strike_all(is_player_team)
	orbital.z_index = 9999
