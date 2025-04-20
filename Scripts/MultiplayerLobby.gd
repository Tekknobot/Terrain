extends Control

const SERVER_PORT = 4242  # Adjust as needed
const MAX_CLIENTS = 4

# Path where we persist settings
const CONFIG_PATH = "user://settings.cfg"
const CONFIG_SECTION = "network"
const CONFIG_KEY_LAST_IP = "last_ip"

@onready var host_button       = $VBoxContainer/HostButton
@onready var join_button       = $VBoxContainer/JoinButton
@onready var back_button       = $VBoxContainer/BackButton
@onready var address_line_edit = $VBoxContainer/AddressLineEdit

func _ready():
	GameData.multiplayer_mode = true
	_load_last_ip()

	# Connect UI signals
	host_button.connect("pressed", Callable(self, "_on_HostButton_pressed"))
	join_button.connect("pressed", Callable(self, "_on_JoinButton_pressed"))
	back_button.connect("pressed", Callable(self, "_on_BackButton_pressed"))

# ---------------------------
#    CONFIG HELPERS
# ---------------------------
func _load_last_ip() -> void:
	var cfg = ConfigFile.new()
	if cfg.load(CONFIG_PATH) == OK:
		address_line_edit.text = cfg.get_value(CONFIG_SECTION, CONFIG_KEY_LAST_IP, "0.0.0.0")
	else:
		# No config → default
		address_line_edit.text = "0.0.0.0"

func _save_last_ip(ip: String) -> void:
	var cfg = ConfigFile.new()
	cfg.load(CONFIG_PATH) # ignore load errors
	cfg.set_value(CONFIG_SECTION, CONFIG_KEY_LAST_IP, ip)
	cfg.save(CONFIG_PATH)

# ---------------------------
#    HOST BUTTON PRESSED
# ---------------------------
func _on_HostButton_pressed():
	var nm = get_node("/root/NetworkManager")
	if nm.host_game(SERVER_PORT, MAX_CLIENTS):
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

	# Save to config
	_save_last_ip(ip_address)

	var nm = get_node("/root/NetworkManager")
	if nm.join_game(ip_address, SERVER_PORT):
		await wait_for_state_ready()
	else:
		print("Failed to join game.")

func wait_for_state_ready() -> void:
	while not get_node("/root/NetworkManager").state_ready:
		await get_tree().create_timer(0.5).timeout
	get_tree().change_scene_to_file("res://Scenes/Main.tscn")

# ---------------------------
#    BACK BUTTON PRESSED
# ---------------------------
func _on_BackButton_pressed():
	GameData.multiplayer_mode = false
	get_tree().change_scene_to_file("res://Scenes/TitleScreen.tscn")
