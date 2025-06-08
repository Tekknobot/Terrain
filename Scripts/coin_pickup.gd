extends Area2D

@export var coin_value: int = 5
@export var wiggle_amplitude: float = 4.0
@export var wiggle_speed: float = 3.0
@export var rotate_speed: float = 1.5  # Radians per second

var base_y: float

func _ready():
	monitoring = true  # <- add this if it's not set in the inspector	
	connect("area_entered", Callable(self, "_on_area_entered"))
	base_y = position.y
	set_process(true)

func _process(delta):
	# Wiggle the coin vertically with a sine wave
	var t = Time.get_ticks_msec() / 1000.0
	position.y = base_y + sin(t * wiggle_speed) * wiggle_amplitude
	
	# Rotate the coin slowly over time
	rotation += rotate_speed * delta

func _on_area_entered(area):
	if area.is_in_group("Units"):
		GameData.coins += coin_value
		print("💰 Collected", coin_value, "coins! Total:", GameData.coins)
		
		# Play SFX
		$AudioStreamPlayer2D.play()
		
		# Wait for sound to finish, then free
		await $AudioStreamPlayer2D.finished
		queue_free()
