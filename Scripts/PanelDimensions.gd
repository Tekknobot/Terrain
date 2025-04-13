extends Panel

@export var padding: Vector2 = Vector2(50, 25)  # Padding for each side.

func _process(_delta: float) -> void:
	_update_size()

func _update_size() -> void:
	var union_rect: Rect2
	var first_child_found: bool = false

	# Iterate over direct children that are Control nodes.
	for child in get_children():
		if child is Control:
			var child_rect: Rect2 = child.get_global_rect()
			if not first_child_found:
				union_rect = child_rect
				first_child_found = true
			else:
				union_rect = union_rect.merge(child_rect)
	
	if first_child_found:
		# Convert the union rectangle (global) into the Panel's local space.
		var local_union: Rect2 = Rect2(union_rect.position - global_position, union_rect.size)
		# Set the Panel’s size to cover the union plus padding on left/right and top/bottom.
		size = local_union.size + padding * 2
		# Optionally, offset the Panel’s position so that it includes the desired padding on the top and left.
		# Uncomment the following line if you want the Panel to reposition itself.
		# rect_position = local_union.position - padding
	else:
		size = Vector2.ZERO
