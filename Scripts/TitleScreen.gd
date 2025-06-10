extends Control

# Get references to the UI elements.
@onready var play_button = $CenterContainer/VBoxContainer/Play
@onready var multiplayer_button = $CenterContainer/VBoxContainer/Multiplayer
@onready var quit_button = $CenterContainer/VBoxContainer/Quit

func _ready() -> void:
	# Optionally, play background music or start animations here.
	# For instance, you could use Tween to fade in the title.
	play_button.grab_focus()  # Give focus to the Play button for gamepad support.
	
	# Connect signals if you haven't connected them in the editor.
	play_button.pressed.connect(_on_PlayButton_pressed)
	multiplayer_button.pressed.connect(_on_MultiplayerButton_pressed)
	quit_button.pressed.connect(_on_QuitButton_pressed)

func _on_PlayButton_pressed() -> void:
	# Transition to your main game scene.
	get_tree().change_scene_to_file("res://Scenes/Main.tscn")

func _on_MultiplayerButton_pressed() -> void:
	get_tree().change_scene_to_file("res://Scenes/MultiplayerLobby.tscn")	# add_child(options_dialog)

func _on_QuitButton_pressed() -> void:
	get_tree().quit()
