extends Node

# Music player node
var player: AudioStreamPlayer
var playlist: Array[AudioStream] = []
var current_track_index := 0
var rng := RandomNumberGenerator.new()

# === NEW: user-facing settings ===
@export_range(0.0, 1.0, 0.01)
var volume_linear: float = 1.0
var muted: bool = false

const SETTINGS_PATH := "user://settings.cfg"
const SETTINGS_SECTION := "audio"

func _ready():
	rng.randomize()

	player = AudioStreamPlayer.new()
	add_child(player)
	player.finished.connect(_on_player_finished)

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

	# === NEW: load saved settings before playing
	_load_settings()
	_apply_volume()

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
	if playlist.size() <= 1:
		return current_track_index
	var next_index := current_track_index
	while next_index == current_track_index:
		next_index = rng.randi_range(0, playlist.size() - 1)
	return next_index

# === NEW: volume/mute helpers ===
func set_volume_linear(v: float) -> void:
	volume_linear = clamp(v, 0.0, 1.0)
	_apply_volume()
	_save_settings()

func get_volume_linear() -> float:
	return volume_linear

func set_muted(m: bool) -> void:
	muted = m
	_apply_volume()
	_save_settings()

func is_muted() -> bool:
	return muted

func _apply_volume() -> void:
	if not player:
		return
	if muted or volume_linear <= 0.001:
		player.volume_db = -80.0  # effectively silent
	else:
		player.volume_db = linear_to_db(volume_linear)

func _save_settings() -> void:
	var cfg := ConfigFile.new()
	# Ignore load errors; we’ll just overwrite
	cfg.load(SETTINGS_PATH)
	cfg.set_value(SETTINGS_SECTION, "volume", volume_linear)
	cfg.set_value(SETTINGS_SECTION, "muted", muted)
	cfg.save(SETTINGS_PATH)

func _load_settings() -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load(SETTINGS_PATH)
	if err == OK:
		volume_linear = float(cfg.get_value(SETTINGS_SECTION, "volume", 1.0))
		muted = bool(cfg.get_value(SETTINGS_SECTION, "muted", false))
