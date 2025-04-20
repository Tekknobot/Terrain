extends Control

const SERVER_PORT = 4242  # Adjust as needed
const MAX_CLIENTS = 4

@onready var host_button = $VBoxContainer/HostButton
@onready var join_button = $VBoxContainer/JoinButton
@onready var back_button = $VBoxContainer/BackButton
@onready var address_line_edit = $VBoxContainer/AddressLineEdit

func _ready():
	GameData.multiplayer_mode = true
	
	# Connect signals using Callable syntax
	host_button.connect("pressed", Callable(self, "_on_HostButton_pressed"))
	join_button.connect("pressed", Callable(self, "_on_JoinButton_pressed"))
	back_button.connect("pressed", Callable(self, "_on_BackButton_pressed"))
	
	# Set default IP if needed
	address_line_edit.text = "192.168.0.31"

# ---------------------------
#    HOST BUTTON PRESSED
# ---------------------------
func _on_HostButton_pressed():
	var nm = get_node("/root/NetworkManager")
	if nm.host_game(SERVER_PORT, MAX_CLIENTS):
		# As the host, change to the main game scene immediately.
		get_tree().change_scene_to_file("res://Scenes/Main.tscn")
	else:
		print("Failed to host game.")

# ---------------------------
#    JOIN BUTTON PRESSED
# ---------------------------
func _on_JoinButton_pressed():
	var ip_address = address_line_edit.text.strip_edges()
	if ip_address == "":
		push_error("Please enter a valid IP address!")
		return
	
	var nm = get_node("/root/NetworkManager")
	if nm.join_game(ip_address, SERVER_PORT):
		# Instead of changing scene immediately, wait until the game state is ready.
		await wait_for_state_ready()
	else:
		print("Failed to join game.")

func wait_for_state_ready() -> void:
	# Wait until the NetworkManager signals that the state is ready.
	# Using a simple loop with a timer:
	while not get_node("/root/NetworkManager").state_ready:
		await get_tree().create_timer(0.5).timeout
	# Once state is ready, change to the main game scene.
	get_tree().change_scene_to_file("res://Scenes/Main.tscn")

# ---------------------------
#    BACK BUTTON PRESSED
# ---------------------------
func _on_BackButton_pressed():
	print("Returning to the title screen...")
	GameData.multiplayer_mode = false
	get_tree().change_scene_to_file("res://Scenes/TitleScreen.tscn")
