extends Node

@export var controller_name := "LightningController"

@onready var _timer := Timer.new()
var _elapsed := 0.0
var _duration := 0.0
var _interval := 0.0
var _strikes_per := 0
var _damage := 0

const LightningStrike = preload("res://Scripts/LightningStrike.gd")

var _is_player_team := true

func start(duration: float, interval: float, strikes_per_interval: int, damage: int, is_player_team: bool) -> void:
	_duration = duration
	_interval = interval
	_strikes_per = strikes_per_interval
	_damage = damage
	_is_player_team = is_player_team  # 🔥 store which team triggered the lightning

	_timer.wait_time = _interval
	_timer.one_shot = false
	add_child(_timer)
	_timer.connect("timeout", Callable(self, "_on_timer_timeout"))
	_timer.start()

	set_process(true)
	if _is_player_team:
		print("⚡ LightningController STARTED by Player Team")
	else:
		print("⚡ LightningController STARTED by Enemy Team")

func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= _duration:
		_timer.stop()
		queue_free()

func _on_timer_timeout() -> void:
	# Get all Area2D units in "Units" group that are NOT players
	var all_units = get_tree().get_nodes_in_group("Units").filter(func(u):
		return u is Area2D and u.has_meta("is_player") and u.is_player != _is_player_team
	)

	if all_units.is_empty():
		print("⚡ No enemy units to strike.")
		return

	print("⚡ Lightning volley triggered. Enemy targets in range:", all_units.size())

	var candidates = all_units.duplicate()
	for i in range(_strikes_per):
		if candidates.is_empty():
			break
		var idx = randi() % candidates.size()
		var target = candidates[idx]
		candidates.remove_at(idx) 
		_strike(target)


func _strike(unit: Area2D) -> void:
	var strike = LightningStrike.new()
	get_tree().get_current_scene().add_child(strike)
	strike.fire(unit, _damage, _is_player_team)

	print("⚡ Striking:", unit.name, "at", unit.global_position)
