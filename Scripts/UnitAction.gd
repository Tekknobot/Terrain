# UnitAction.gd
extends Resource
class_name UnitAction

@export var type: String
@export var target: Vector2i
@export var path: Array = []
@export var score: int = 0

func _init(t: String="", tg: Vector2i=Vector2i(-1,-1), p: Array=[]):
	type = t
	target = tg
	path = p
	score = 0
