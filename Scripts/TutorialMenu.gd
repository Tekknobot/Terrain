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

• [color=yellow]Left‑click[/color] (or tap) to [color=green]select[/color] a unit  
• [color=yellow]Right‑click[/color] (or hold) to enter [color=red]attack mode[/color]  
• [color=gray]Scroll Wheel[/color] to [color=blue]zoom[/color]"""

func _on_terrain_pressed() -> void:
	info_label.text = """[b][color=orange]Terrain Effects[/color][/b]

• [color=green]Grass[/color]: +5 HP when standing on it  
• [color=white]Snow[/color]: −1 attack range  
• [color=cyan]Ice[/color]: −2 attack range  
• [color=brown]Road[/color] (Down‑Right / Down‑Left): +1 movement  
• [color=purple]Intersection[/color]: +2 movement"""

func _on_abilities_pressed() -> void:
	info_label.text = """[b][color=orange]Special Abilities[/color][/b]

[b][color=red]Ground Slam       [/color][/b]  Shockwaves damage all adjacent tiles (even empty ones)  
[b][color=red]Mark & Pounce     [/color][/b]  Lock onto a target tile, leap in, and deliver a lethal strike  
[b][color=red]High‑Arcing Shot  [/color][/b]  Lands in a 3×3 zone — heavy center damage  
[b][color=red]Suppressive Fire  [/color][/b]  Line of fire up to 4 tiles — enemies in the path take damage  
[b][color=red]Guardian Halo     [/color][/b]  Grant a one‑round shield to an ally (lost if you miss)  
[b][color=red]Fortify           [/color][/b]  Halve all incoming damage until your next turn  
[b][color=red]Heavy Rain        [/color][/b]  Call down a devastating missile barrage on the battlefield  
[b][color=red]Web Field         [/color][/b]  Explosives ensnare and damage all foes in the zone"""

func _on_push_pressed() -> void:
	info_label.text = """[b][color=orange]Push Mechanic[/color][/b]

[color=red]Knock enemies[/color] into [color=blue]hazards[/color]—[color=blue]water tiles[/color], [color=gray]off‑map edges[/color] or [color=gray]obstacles[/color]—for [color=red]instant elimination[/color]."""

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://Scenes/TitleScreen.tscn")
