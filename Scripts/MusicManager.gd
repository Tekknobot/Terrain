extends Node

# Music player node
var player: AudioStreamPlayer
# List of tracks to play (fill in or set from code)
var playlist: Array[AudioStream] = []
var current_track_index := 0

func _ready():
	# Create an AudioStreamPlayer once, no re-adding or destroying
	player = AudioStreamPlayer.new()
	add_child(player)
	player.finished.connect(_on_player_finished)

	# Example playlist setup (replace with your own audio files)
	playlist = [
		preload("res://Audio/Music/Track 1.wav")
	]

	play_current_track()

func play_current_track():
	if playlist.is_empty():
		return

	player.stream = playlist[current_track_index]
	player.play()

func _on_player_finished():
	current_track_index = (current_track_index + 1) % playlist.size()
	play_current_track()
