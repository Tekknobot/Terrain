extends Area2D

@export var heal_amount: int = 15
@export var wiggle_amplitude: float = 4.0
@export var wiggle_speed: float = 3.0
@export var rotate_speed: float = 1.5

var base_y: float

func _ready():
	monitoring = true
	set_deferred("monitoring", true)
	connect("area_entered", Callable(self, "_on_trigger_entered"))
	connect("body_entered", Callable(self, "_on_trigger_entered"))
	base_y = position.y
	set_process(true)
	print("[HealthPickup] Ready. Monitoring=", monitoring)

func _process(delta):
	var t = Time.get_ticks_msec() / 1000.0
	position.y = base_y + sin(t * wiggle_speed) * wiggle_amplitude
	rotation += rotate_speed * delta

func _on_trigger_entered(other):
	print("[HealthPickup] Overlap from:", other.name, " groups=", other.get_groups())

	var unit = other
	if not unit.is_in_group("Units"):
		if unit.get_parent() and unit.get_parent().is_in_group("Units"):
			unit = unit.get_parent()
		else:
			return

	if not unit.has_method("update_health_bar"):
		return
	if not "health" in unit or not "max_health" in unit:
		return

	var before = unit.health
	unit.health = min(unit.max_health, unit.health + heal_amount)
	var after = unit.health
	var healed = after - before

	if healed > 0:
		print("❤️ Healed", unit.name, "for", healed, "HP.")
		if unit.has_method("flash_blue"):
			unit.flash_blue()
		unit.update_health_bar()
	else:
		print("❤️ Pickup collected but", unit.name, "was already full HP.")

	# Local reinforcement spawn (no networking)
	var tilemap := get_node_or_null("/root/BattleGrid/TileMap")
	if tilemap:
		var is_player_team = unit.is_player
		tilemap.spawn_reinforcement(is_player_team)

	if has_node("AudioStreamPlayer2D"):
		$AudioStreamPlayer2D.play()
		await $AudioStreamPlayer2D.finished

	queue_free()
