extends Control

@onready var controls_btn      = $CenterContainer/VBoxContainer/ControlsBtn
@onready var terrain_btn       = $CenterContainer/VBoxContainer/TerrainBtn
@onready var abilities_btn     = $CenterContainer/VBoxContainer/AbilitiesBtn
@onready var push_btn          = $CenterContainer/VBoxContainer/PushBtn
@onready var back_btn          = $CenterContainer/VBoxContainer/BackBtn
@onready var info_label        = $InfoPanel/InfoLabel

func _ready() -> void:
	controls_btn.pressed.connect(_on_controls_pressed)
	terrain_btn.pressed.connect(_on_terrain_pressed)
	abilities_btn.pressed.connect(_on_abilities_pressed)
	push_btn.pressed.connect(_on_push_pressed)
	back_btn.pressed.connect(_on_back_pressed)

func _on_controls_pressed() -> void:
	info_label.text = """[b][color=orange]Controls[/color][/b]

[color=yellow]Left click[/color] or tap to [color=green]select[/color] a unit  
[color=yellow]Right click[/color] or hold to enter [color=red]attack mode[/color]  
[color=gray]Scroll Wheel[/color] to [color=blue]zoom[/color]"""

func _on_terrain_pressed() -> void:
	info_label.text = """[b][color=orange]Terrain Effects[/color][/b]

[color=green]Grass[/color] gains 5 HP when standing on it  
[color=white]Snow[/color] reduces attack range by 1  
[color=cyan]Ice[/color] reduces attack range by 2  
[color=brown]Road[/color] move 1 tile further on down right or down left  
[color=purple]Intersection[/color] move 2 tiles further"""

func _on_abilities_pressed() -> void:
	info_label.text = """[b][color=orange]Special Abilities[/color][/b]

[b][color=red]Ground Slam [/color][/b] shockwave hits all adjacent tiles even if empty  
[b][color=red]Mark and Pounce [/color][/b] lock target leap in and strike with high damage  
[b][color=red]High Arcing Shot [/color][/b] lands in 3x3 zone strong damage in center  
[b][color=red]Suppressive Fire [/color][/b] fire in line up to 4 tiles damaging all in path  
[b][color=red]Guardian Halo [/color][/b] give ally one round shield lost if missed  
[b][color=red]Fortify [/color][/b] reduce all damage taken until next turn  
[b][color=red]Heavy Rain [/color][/b] missile barrage over wide area heavy damage  
[b][color=red]Web Field [/color][/b] trap and damage all enemies in the zone"""

func _on_push_pressed() -> void:
	info_label.text = """[b][color=orange]Push Mechanic[/color][/b]

[color=red]Knock enemies[/color] into [color=blue]hazards[/color] like [color=blue]water tiles[/color] [color=gray]map edges[/color] or [color=gray]obstacles[/color] for [color=red]instant elimination[/color]"""

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://Scenes/TitleScreen.tscn")
