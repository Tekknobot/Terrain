extends Control

@onready var push_btn      		= $CenterContainer/VBoxContainer/PushBtn
@onready var impact_btn		= $CenterContainer/VBoxContainer/ImpactBtn
@onready var abilities_btn 		= $CenterContainer/VBoxContainer/AbilitiesBtn
@onready var tips_btn      		= $CenterContainer/VBoxContainer/TipsBtn
@onready var back_btn      		= $CenterContainer/VBoxContainer/BackBtn
@onready var player          	= $PanelContainer/VideoPlayer
@onready var panel_container 	= $PanelContainer

# Define playlists for each module
var playlists = {
	"push": [
		"res://Video/Tutorial/push_1.ogv",
		"res://Video/Tutorial/push_2.ogv",
		"res://Video/Tutorial/push_3.ogv"
	],
	"ranged": [
		"res://Video/Tutorial/push_4.ogv",
		"res://Video/Tutorial/push_5.ogv",
		"res://Video/Tutorial/push_6.ogv"
	],	
	"abilities": [
		"res://Video/Tutorial/dash.ogv",
		"res://Video/Tutorial/double_jump.ogv",
		"res://Video/Tutorial/grapple.ogv"
	],
	"tips": [
		"res://Video/Tutorial/physics_tweaks.ogv",
		"res://Video/Tutorial/collision_shapes.ogv"
	]
}

var current_list = []
var current_index : int = 0

func _ready() -> void:
	# connect with bound arguments instead of lambdas
	push_btn.pressed.connect(Callable(self, "_start_tutorial").bind("push"))
	impact_btn.pressed.connect(Callable(self, "_start_tutorial").bind("ranged"))
	abilities_btn.pressed.connect(Callable(self, "_start_tutorial").bind("abilities"))
	tips_btn.pressed.connect(Callable(self, "_start_tutorial").bind("tips"))
	back_btn.pressed.connect(Callable(self, "_on_Back_pressed"))
	
	player.scale = Vector2(0.5, 0.5)
	
	player.visible = false
	player.autoplay = false
	player.connect("finished", Callable(self, "_on_Video_finished"))

func _start_tutorial(module_name: String) -> void:
	if not playlists.has(module_name):
		push_error("No videos for module: %s" % module_name)
		return
	current_list = playlists[module_name]  # now correctly an Array[String]
	current_index = 0
	_play_current_video()

func _play_current_video() -> void:
	player.stream = ResourceLoader.load(current_list[current_index])
	player.visible = true
	panel_container.visible = true
	player.play()

func _on_Video_finished() -> void:
	current_index += 1
	if current_index < current_list.size():
		_play_current_video()
	else:
		# End of module: hide player, show menu again
		player.visible = false
		panel_container.visible = false

func _on_Back_pressed() -> void:
	# Return to main menu
	get_tree().change_scene_to_file("res://Scenes/TitleScreen.tscn")
