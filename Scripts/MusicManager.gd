extends Node

# --- Player & playlist ---
var player: AudioStreamPlayer
var playlist: Array[AudioStream] = []
var current_track_index := 0
var rng := RandomNumberGenerator.new()

# --- User-facing state (mirrors Settings panel) ---
@export_range(0.0, 1.0, 0.01)
var volume_linear: float = 1.0
var muted: bool = false

# --- Persistence ---
const SETTINGS_PATH := "user://settings.cfg"
const SECTION := "audio"
const KEY_VOL := "music"          # matches your Settings UI
const KEY_MUTED := "music_muted"  # matches your Settings UI

func _ready() -> void:
	rng.randomize()

	player = AudioStreamPlayer.new()
	# Optional: route to a "Music" bus you created in the Project Settings
	# player.bus = "Music"
	add_child(player)
	player.finished.connect(_on_player_finished)

	# Build your playlist (keep your paths)
	playlist = [
		preload("res://Audio/Music/Faded.mp3"),
		preload("res://Audio/Music/Future.mp3"),
		preload("res://Audio/Music/Summer.mp3"),
		preload("res://Audio/Music/Jam.mp3"),
		preload("res://Audio/Music/Nightmode.mp3"),
		preload("res://Audio/Music/Pumped.mp3"),
	]

	if not playlist.is_empty():
		current_track_index = rng.randi_range(0, playlist.size() - 1)

	# Load settings before starting any playback
	_load_settings()
	_apply_volume()

	play_current_track()

# -----------------------
# Playback
# -----------------------
func play_current_track() -> void:
	if playlist.is_empty():
		return
	player.stream = playlist[current_track_index]
	player.play()

func _on_player_finished() -> void:
	current_track_index = _pick_next_index_no_repeat()
	play_current_track()

func _pick_next_index_no_repeat() -> int:
	if playlist.size() <= 1:
		return current_track_index
	var next_index := current_track_index
	while next_index == current_track_index:
		next_index = rng.randi_range(0, playlist.size() - 1)
	return next_index

# -----------------------
# Public API used by Settings window
# -----------------------
func set_volume_linear(v: float) -> void:
	volume_linear = clamp(v, 0.0, 1.0)
	_apply_volume()
	_save_settings()

func get_volume_linear() -> float:
	return volume_linear

func set_muted(m: bool) -> void:
	muted = m
	_apply_volume()
	# If we’re unmuting and nothing is playing (web can suspend), resume
	if not muted:
		if not player.stream and not playlist.is_empty():
			player.stream = playlist[current_track_index]
		if player.stream and not player.playing:
			# Web nicety: re-play from current pos to “wake” audio contexts
			var pos = max(0.0, player.get_playback_position())
			player.play(pos)
	_save_settings()

func is_muted() -> bool:
	return muted

# -----------------------
# Internals
# -----------------------
func _apply_volume() -> void:
	if not player:
		return
	if muted or volume_linear <= 0.001:
		player.volume_db = -80.0  # effectively silent
	else:
		player.volume_db = linear_to_db(volume_linear)

func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)  # ignore error; we’ll overwrite
	cfg.set_value(SECTION, KEY_VOL, volume_linear)
	cfg.set_value(SECTION, KEY_MUTED, muted)
	cfg.save(SETTINGS_PATH)

func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		# Defaults are safe: full volume, not muted
		volume_linear = float(cfg.get_value(SECTION, KEY_VOL, 1.0))
		muted = bool(cfg.get_value(SECTION, KEY_MUTED, false))
