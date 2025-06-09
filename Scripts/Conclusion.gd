# File: res://Scenes/GameOver.gd
extends Node2D

# These nodes are assumed to exist in the scene.
@onready var result_label = $CanvasLayer/Control/VBoxContainer/ResultLabel
@onready var stats_container = $CanvasLayer/Control/VBoxContainer/StatsContainer
@onready var rewards_container = $CanvasLayer/Control/VBoxContainer/RewardsContainer
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
		result_label.text = "Victory!"
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
	
	# Iterate through the stats dictionary and create labels.
	for key in stats.keys():
		var stat_label = Label.new()
		stat_label.text = "%s: %s" % [key.capitalize(), str(stats[key])]
		stats_container.add_child(stat_label)
	
	# Iterate through the rewards dictionary and create labels.
	for key in rewards.keys():
		var reward_label = Label.new()
		reward_label.text = "%s Earned: %s" % [key.capitalize(), str(rewards[key])]
		rewards_container.add_child(reward_label)
	
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
