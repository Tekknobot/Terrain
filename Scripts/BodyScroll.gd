extends RichTextLabel

@export var scroll_speed: float = 20.0   # pixels per second
@export var start_offset: float = 100.0  # how far below the visible area to start
@export var top_buffer: float = 50.0     # how far past the top before stopping

var start_pos_y: float
var scroll_done: bool = false

func _ready():
	# Start the label below its normal position
	start_pos_y = position.y + start_offset
	position.y = start_pos_y

func _process(delta: float):
	if scroll_done:
		return

	position.y -= scroll_speed * delta

	# Once the label's bottom passes above the top + buffer, stop scrolling
	if position.y + size.y < -top_buffer:
		scroll_done = true
		_on_scroll_finished()

func _on_scroll_finished():
	# Optional: queue_free(), emit a signal, or do whatever when done
	print("Scrolling finished!")
	queue_free()
