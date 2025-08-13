extends Node

# Music player node
var player: AudioStreamPlayer
# List of tracks to play (fill in or set from code)
var playlist: Array[AudioStream] = []
var current_track_index := 0
var rng := RandomNumberGenerator.new()

func _ready():
	rng.randomize()

	# Create an AudioStreamPlayer once, no re-adding or destroying
	player = AudioStreamPlayer.new()
	add_child(player)
	player.finished.connect(_on_player_finished)

	# Example playlist setup (replace with your own audio files)
	playlist = [
		preload("res://Audio/Music/Faded.mp3"),
		preload("res://Audio/Music/Future.mp3"),
		preload("res://Audio/Music/Summer.mp3"),
		preload("res://Audio/Music/Jam.mp3"),
		preload("res://Audio/Music/Nightmode.mp3"),
		preload("res://Audio/Music/Pumped.mp3"),
	]

	# Start from a random track
	if not playlist.is_empty():
		current_track_index = rng.randi_range(0, playlist.size() - 1)

	play_current_track()

func play_current_track():
	if playlist.is_empty():
		return
	player.stream = playlist[current_track_index]
	player.play()

func _on_player_finished():
	current_track_index = _pick_next_index_no_repeat()
	play_current_track()

func _pick_next_index_no_repeat() -> int:
	# If there's only one track, just keep playing it
	if playlist.size() <= 1:
		return current_track_index

	var next_index := current_track_index
	# Keep rolling until it's different from the current one
	while next_index == current_track_index:
		next_index = rng.randi_range(0, playlist.size() - 1)
	return next_index
