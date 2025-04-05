extends Control

# Get references to the UI elements.
@onready var play_button = $CenterContainer/VBoxContainer/Play
@onready var options_button = $CenterContainer/VBoxContainer/Options
@onready var quit_button = $CenterContainer/VBoxContainer/Quit

func _ready() -> void:
	# Optionally, play background music or start animations here.
	# For instance, you could use Tween to fade in the title.
	play_button.grab_focus()  # Give focus to the Play button for gamepad support.
	
	# Connect signals if you haven't connected them in the editor.
	play_button.pressed.connect(_on_PlayButton_pressed)
	options_button.pressed.connect(_on_OptionsButton_pressed)
	quit_button.pressed.connect(_on_QuitButton_pressed)

func _on_PlayButton_pressed() -> void:
	# Transition to your main game scene.
	get_tree().change_scene_to_file("res://Scenes/Main.tscn")

func _on_OptionsButton_pressed() -> void:
	# You can either open an options popup or switch to an options scene.
	print("Options button pressed")
	# For example, show an options dialog:
	# var options_dialog = preload("res://Scenes/OptionsDialog.tscn").instantiate()
	# add_child(options_dialog)

func _on_QuitButton_pressed() -> void:
	get_tree().quit()
