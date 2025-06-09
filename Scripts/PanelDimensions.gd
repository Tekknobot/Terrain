extends Panel

@export var padding: Vector2 = Vector2(20, 20)

func _ready():
	# Optional: ensure initial update
	_update_size()

func _process(_delta: float) -> void:
	_update_size()

func _update_size() -> void:
	var bounds := Rect2()
	var first := true

	for child in get_children():
		if child is Control:
			var offset = child.position
			var size = child.get_combined_minimum_size()

			var rect := Rect2(offset, size)
			if first:
				bounds = rect
				first = false
			else:
				bounds = bounds.merge(rect)

	if not first:
		# Instead of modifying position directly, apply margin-like expansion
		var padded_position = bounds.position - padding
		var padded_size = bounds.size + padding * 2

		position = padded_position
		size = padded_size
