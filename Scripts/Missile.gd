extends Node2D

signal finished

@export var missile_speed: float = 2.0
@export var pixel_size: int = 2  # Ensures pixel-perfect snapping

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

	# Try to get a dedicated missile trail node from the current scene.
	var scene = get_tree().get_current_scene()
	line_renderer = scene.get_node("MissileTrail")
	
	if line_renderer:
		line_renderer.clear_points()
		line_renderer.visible = true
		# Use the average Y of start and end to sort depth.
		var avg_y = (start_pos.y + end_pos.y) / 2
		line_renderer.z_index = int(avg_y)
		line_renderer.z_as_relative = false  # Use global z, not relative to parent

		line_renderer.clear_points()
		line_renderer.visible = false
		line_renderer.width = pixel_size  # Match pixel size

		line_renderer.texture = preload("res://Textures/missile.png")
		line_renderer.texture_mode = Line2D.LINE_TEXTURE_TILE
		line_renderer.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		
		# Optional visual tuning:
		line_renderer.joint_mode = Line2D.LINE_JOINT_BEVEL
		line_renderer.begin_cap_mode = Line2D.LINE_CAP_NONE
		line_renderer.end_cap_mode = Line2D.LINE_CAP_NONE
	else:
		print("❌ Could not find Line2D in scene. No trail will render.")

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

			# Spawn explosion effect at missile impact.
			var explosion_scene = preload("res://Scenes/VFX/Explosion.tscn")
			var explosion = explosion_scene.instantiate()
			explosion.global_position = global_position
			get_tree().get_current_scene().add_child(explosion)
			
			# Get the tile where the missile has landed.
			var tilemap = get_tree().get_current_scene().get_node("TileMap")
			var impact_tile = tilemap.local_to_map(tilemap.to_local(global_position))
			
			# Damage any unit on the impact tile.
			var target_unit = tilemap.get_unit_at_tile(impact_tile)
			if target_unit:
				target_unit.take_damage(40)  # Adjust damage as needed.
				target_unit.flash_white()
			
			# Now check adjacent tiles for structures and units.
			var directions = [
				Vector2i(0, -1), Vector2i(0, 1),
				Vector2i(-1, 0), Vector2i(1, 0)
			]
			for d in directions:
				var adj_tile = impact_tile + d
				
				# Check for a structure on the adjacent tile.
				var structure = tilemap.get_structure_at_tile(adj_tile)
				if structure:
					var anim_sprite = structure.get_node_or_null("AnimatedSprite2D")
					if anim_sprite:
						anim_sprite.play("demolished")
						anim_sprite.get_parent().modulate = Color(1, 1, 1, 1)
				
				# Check for a unit on the adjacent tile.
				var occupant = tilemap.get_unit_at_tile(adj_tile)
				if not occupant:
					continue
				
				# Calculate destination tile by pushing occupant one tile further
				var dest_tile = adj_tile + d
				var is_water = false
				if tilemap.is_within_bounds(dest_tile):
					is_water = (tilemap.get_cell_source_id(0, dest_tile) == tilemap.water_tile_id)
				
				# ── CASE 1: Die if out of bounds or blocked by another unit/structure ──
				if (not tilemap.is_within_bounds(dest_tile)) \
				   or tilemap.get_unit_at_tile(dest_tile) \
				   or tilemap.get_structure_at_tile(dest_tile):
					
					if is_instance_valid(occupant):
						occupant.being_pushed = true
						var dest_pos = tilemap.to_global(tilemap.map_to_local(dest_tile)) + Vector2(0, occupant.Y_OFFSET)
						var push_tween = occupant.create_tween()
						push_tween.tween_property(occupant, "global_position", dest_pos, 0.2) \
								  .set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
						occupant.shake()
						
						await get_tree().create_timer(0.2).timeout
						
						# Before calling die(), turn off being_pushed
						if is_instance_valid(occupant):
							occupant.being_pushed = false
							occupant.die()
						
						# Now damage whoever is at dest_tile (if still valid)
						var occupant_at_dest = tilemap.get_unit_at_tile(dest_tile)
						if occupant_at_dest:
							occupant_at_dest.take_damage(25)
						var struct_at_dest = tilemap.get_structure_at_tile(dest_tile)
						if struct_at_dest:
							var s_anim = struct_at_dest.get_node_or_null("AnimatedSprite2D")
							if s_anim:
								s_anim.play("demolished")
								s_anim.get_parent().modulate = Color(1, 1, 1, 1)
					# Done with this occupant
					continue
				# ──────────────────────────────────────────────────────────────

				# ── CASE 2: Destination is water ──
				elif is_water:
					if is_instance_valid(occupant):
						occupant.being_pushed = true
						var dest_pos = tilemap.to_global(tilemap.map_to_local(dest_tile)) + Vector2(0, occupant.Y_OFFSET)
						var push_tween = occupant.create_tween()
						push_tween.tween_property(occupant, "global_position", dest_pos, 0.2) \
								  .set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
						occupant.shake()
						
						await get_tree().create_timer(0.2).timeout
						
						# After arriving in water, deal damage and play splash
						if is_instance_valid(occupant):
							occupant.take_damage(25)
							tilemap.play_splash_sound(dest_pos)
							occupant.being_pushed = false
					continue
				# ──────────────────────────────────────────────────────────────

				# ── CASE 3: Normal on‐grid push ──
				else:
					if is_instance_valid(occupant):
						occupant.being_pushed = true
						var dest_pos = tilemap.to_global(tilemap.map_to_local(dest_tile)) + Vector2(0, occupant.Y_OFFSET)
						var push_tween = occupant.create_tween()
						push_tween.tween_property(occupant, "global_position", dest_pos, 0.2) \
								  .set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

						# Update its logical tile, deal damage, and shake
						occupant.tile_pos = dest_tile
						occupant.take_damage(25)
						occupant.shake()
						
						await get_tree().create_timer(0.2).timeout
						
						if is_instance_valid(occupant):
							occupant.being_pushed = false
				# ──────────────────────────────────────────────────────────────

			# end for directions
			
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
	# Adjust the control point for a nice arc (here offset upward by 200 pixels).
	control_point = (start + target) / 2 + Vector2(0, -200)

	global_position = start_pos
	visible = true
	is_ready = true

	if line_renderer:
		line_renderer.clear_points()
		line_renderer.visible = true  # Show trail
