extends Area2D

@export var heal_amount: int = 15
@export var wiggle_amplitude: float = 4.0
@export var wiggle_speed: float = 3.0
@export var rotate_speed: float = 1.5  # Radians per second

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
	if area.is_in_group("Units") and area.has_method("update_health_bar"):
		var before = area.health
		area.health = min(area.max_health, area.health + heal_amount)
		var after = area.health

		if before != after:
			print("❤️ Healed", area.name, "for", after - before, "HP.")

			# Optional: flash or VFX
			if area.has_method("flash_blue"):
				area.flash_blue()

			area.update_health_bar()

		# Play pickup SFX
		$AudioStreamPlayer2D.play()

		# Wait for SFX to end before destroying
		await $AudioStreamPlayer2D.finished
		queue_free()
