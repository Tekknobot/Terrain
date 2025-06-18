extends Node

@export var region_scenes: Array[PackedScene] = []
@onready var map = $Overworld

func _ready():
	map.connect("region_selected", Callable(self, "_on_region_selected"))

func _on_region_selected(idx: int, name: String) -> void:
	if idx < region_scenes.size():
		# stash the target
		GameState.next_region_scene = region_scenes[idx]
		# go to the transition scene
		get_tree().change_scene_to_file("res://Scenes/Transition.tscn")
	else:
		push_error("No scene assigned for region %d" % idx)
