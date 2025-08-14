extends Node2D

signal finished

@export var missile_speed: float = 2.0
@export var pixel_size: int = 2  # Ensures pixel-perfect snapping
@export var damage: int = 40     # Base damage dealt on impact

var start_pos: Vector2 = Vector2.ZERO
var end_pos: Vector2 = Vector2.ZERO
var control_point: Vector2 = Vector2.ZERO
var progress: float = 0.0
var is_ready: bool = false

@onready var sprite: Sprite2D = $Sprite2D
@onready var line_renderer: Line2D = $Line2D

func _ready():
	visible = false
	progress = 0.0

	if line_renderer:
		line_renderer.clear_points()
		line_renderer.visible = false
		line_renderer.width = pixel_size
		line_renderer.texture = preload("res://Textures/missile.png")
		line_renderer.texture_mode = Line2D.LINE_TEXTURE_TILE
		line_renderer.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		line_renderer.joint_mode = Line2D.LINE_JOINT_BEVEL
		line_renderer.begin_cap_mode = Line2D.LINE_CAP_NONE
		line_renderer.end_cap_mode = Line2D.LINE_CAP_NONE

func _process(delta):
	if is_ready and progress < 1.0:
		progress += missile_speed * delta
		var new_position = bezier_point(progress)
		global_position = new_position.snapped(Vector2(pixel_size, pixel_size))
		update_rotation()

		if line_renderer:
			line_renderer.add_point(global_position)
	elif is_ready and progress >= 1.0:
		is_ready = false

		if line_renderer:
			line_renderer.visible = false

		# Spawn explosion effect
		var explosion_scene = preload("res://Scenes/VFX/Explosion.tscn")
		var explosion = explosion_scene.instantiate()
		explosion.global_position = global_position
		get_tree().get_current_scene().add_child(explosion)

		# Handle impact on target tile
		var tilemap = get_tree().get_current_scene().get_node("TileMap")
		var impact_tile = tilemap.local_to_map(tilemap.to_local(global_position))

		# ✅ NEW: check for a structure on the impact tile (direct hit)
		var impact_structure = tilemap.get_structure_at_tile(impact_tile)
		if impact_structure:
			var anim_sprite = impact_structure.get_node_or_null("AnimatedSprite2D")
			if anim_sprite:
				anim_sprite.play("demolished")
				# If you were brightening the structure via parent, also do it here:
				anim_sprite.get_parent().modulate = Color(1, 1, 1, 1)
			# If demolish() immediately frees the node and you want the animation to be seen,
			# consider awaiting the animation end before demolishing:
			# await anim_sprite.animation_finished
			if impact_structure.has_method("demolish"):
				impact_structure.demolish()

		# Damage the unit on the impact tile using exported damage
		var target_unit = tilemap.get_unit_at_tile(impact_tile)
		if target_unit:
			target_unit.take_damage(damage)
			target_unit.flash_white()

		# Check adjacent tiles for structures and units
		var directions = [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]
		for d in directions:
			var adjacent_tile = impact_tile + d

			# Check for a structure on the adjacent tile
			var structure = tilemap.get_structure_at_tile(adjacent_tile)
			if structure:
				var anim_sprite = structure.get_node_or_null("AnimatedSprite2D")
				if anim_sprite:
					anim_sprite.play("demolished")
					anim_sprite.get_parent().modulate = Color(1, 1, 1, 1)
					if structure.has_method("demolish"):
						structure.demolish()				

			# Check for a unit on the adjacent tile
			var occupant = tilemap.get_unit_at_tile(adjacent_tile)
			if occupant:
				occupant.being_pushed = true
				TutorialManager.on_action("push_mechanic")

				var dest_tile = adjacent_tile + d
				var is_water = tilemap.get_cell_source_id(0, dest_tile) == 6

				# If destination is out of bounds or occupied by another unit or structure (and not water), kill the occupant
				if (not tilemap.is_within_bounds(dest_tile)) or tilemap.get_unit_at_tile(dest_tile) or tilemap.get_structure_at_tile(dest_tile):
					var dest_pos = tilemap.to_global(tilemap.map_to_local(dest_tile)) + Vector2(0, occupant.Y_OFFSET)
					var push_tween = occupant.create_tween()
					push_tween.tween_property(occupant, "global_position", dest_pos, 0.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
					occupant.shake()
					await get_tree().create_timer(0.2).timeout
					if not is_instance_valid(occupant):
						if TurnManager.turn_order[TurnManager.current_turn_index] == TurnManager.Team.PLAYER:
							emit_signal("finished")
							tilemap.input_locked = false
							queue_free()
							return
						emit_signal("finished")
						tilemap.input_locked = false
						TurnManager._start_unit_action(TurnManager.Team.ENEMY)
						queue_free()
						return
					occupant.being_pushed = false
					TutorialManager.on_action("collide_mechanic")
					occupant.die()
					var pushed_unit = tilemap.get_unit_at_tile(dest_tile)
					if pushed_unit:
						pushed_unit.take_damage(25)
					if tilemap.get_structure_at_tile(dest_tile):
						var anim_sprite = tilemap.get_structure_at_tile(dest_tile).get_node_or_null("AnimatedSprite2D")
						if anim_sprite:
							anim_sprite.play("demolished")
							anim_sprite.get_parent().modulate = Color(1, 1, 1, 1)
	
						var dest_structure = tilemap.get_structure_at_tile(dest_tile)
						if dest_structure and dest_structure.has_method("demolish"):
							dest_structure.demolish()
						
				# Else if destination is water, animate push and apply 25 damage
				elif is_water:
					var dest_pos = tilemap.to_global(tilemap.map_to_local(dest_tile)) + Vector2(0, occupant.Y_OFFSET)
					var push_tween = occupant.create_tween()
					push_tween.tween_property(occupant, "global_position", dest_pos, 0.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
					occupant.shake()
					await get_tree().create_timer(0.2).timeout
					if not is_instance_valid(occupant):
						if TurnManager.turn_order[TurnManager.current_turn_index] == TurnManager.Team.PLAYER:
							emit_signal("finished")
							tilemap.input_locked = false
							queue_free()
							return
						emit_signal("finished")
						tilemap.input_locked = false
						TurnManager._start_unit_action(TurnManager.Team.ENEMY)
						queue_free()
						return
					occupant.being_pushed = false
					occupant.take_damage(25)
					tilemap.play_splash_sound(dest_pos)
				else:
					# Otherwise, push normally and apply 25 damage
					var dest_pos = tilemap.to_global(tilemap.map_to_local(dest_tile)) + Vector2(0, occupant.Y_OFFSET)
					var push_tween = occupant.create_tween()
					push_tween.tween_property(occupant, "global_position", dest_pos, 0.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
					occupant.tile_pos = dest_tile
					occupant.take_damage(25)
					occupant.shake()

					if tilemap.get_structure_at_tile(dest_tile):
						var anim_sprite = tilemap.get_structure_at_tile(dest_tile).get_node_or_null("AnimatedSprite2D")
						if anim_sprite:
							anim_sprite.play("demolished")
							anim_sprite.get_parent().modulate = Color(1, 1, 1, 1)
							
						var dest_structure = tilemap.get_structure_at_tile(dest_tile)
						if dest_structure and dest_structure.has_method("demolish"):
							dest_structure.demolish()
														
					await get_tree().create_timer(0.2).timeout
					if not is_instance_valid(occupant):
						if TurnManager.turn_order[TurnManager.current_turn_index] == TurnManager.Team.PLAYER:
							emit_signal("finished")
							tilemap.input_locked = false
							queue_free()
							return
						emit_signal("finished")
						tilemap.input_locked = false
						TurnManager._start_unit_action(TurnManager.Team.ENEMY)
						queue_free()
						return
					occupant.being_pushed = false

		emit_signal("finished")
		queue_free()

		z_index = int(global_position.y)
		z_as_relative = false

func bezier_point(t: float) -> Vector2:
	var p0 = start_pos
	var p1 = control_point
	var p2 = end_pos
	return (1 - t) * (1 - t) * p0 + 2 * (1 - t) * t * p1 + t * t * p2

func update_rotation():
	var next_pos = bezier_point(min(progress + 0.05, 1.0))
	var direction = next_pos - global_position
	sprite.rotation = direction.angle()

func set_target(start: Vector2, target: Vector2):
	start_pos = start
	end_pos = target
	control_point = (start + target) / 2 + Vector2(0, -200)

	global_position = start_pos
	visible = true
	is_ready = true

	if line_renderer:
		line_renderer.clear_points()
		line_renderer.visible = true
