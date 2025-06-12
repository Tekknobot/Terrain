# File: res://Scenes/GameOver.gd
extends Node2D

# These nodes are assumed to exist in the scene.
@onready var result_label = $CanvasLayer/Control/ResultLabel
@onready var audio_player = $AudioStreamPlayer2D

# Preload your audio streams.
@export var victory_sound: AudioStream
@export var defeat_sound: AudioStream

func _ready():
	var path = "CanvasLayer/Control/VBoxContainer/ResultLabel"
	var r = get_node(path)
	if r == null:
		print("Error: Could not find node at path: ", path)
		print("Children of root node:")
		for child in get_children():
			print(child.name)
	else:
		print("ResultLabel found:", r)

# This function is used to update the screen with match data.
func set_result(result: String, stats: Dictionary, rewards: Dictionary) -> void:
	# Update the result label without using a ternary.
	if result == "win":
		result_label.text = "Victory Upgrades!"
				
		# Play the victory sound.
		if victory_sound:
			audio_player.stream = victory_sound
			audio_player.play()
		else:
			push_warning("Victory sound not assigned!")
	else:
		result_label.text = "Defeat!"
		# Play the defeat sound.
		if defeat_sound:
			audio_player.stream = defeat_sound
			audio_player.play()
		else:
			push_warning("Defeat sound not assigned!")
	
	# Optionally, play an animation or sound here.
	show()  # Ensure the screen is visible.

func _on_RetryButton_pressed():
	# Reload the current scene to try again.
	get_tree().reload_current_scene()

func _on_MainMenuButton_pressed():
	# Change to the main menu scene.
	get_tree().change_scene_to_file("res://Scenes/MainMenu.tscn")

func _on_ContinueButton_pressed():
	# Change to the main game scene (battle) instead of resetting entire game
	get_tree().change_scene_to_file("res://Scenes/Main.tscn")
