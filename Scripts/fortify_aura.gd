extends Node2D

@onready var parts := $Particles2D

func _ready():
	# Begin emission immediately, then free after lifetime.
	parts.emitting = true
	# Wait the particles’ lifetime plus a bit, then free:
	await get_tree().create_timer(parts.lifetime + 0.1).timeout
	queue_free()
