extends Control

const SERVER_PORT = 4242  # Adjust to any unused port on your network
const MAX_CLIENTS = 4     # How many total clients you want to allow

@onready var host_button = $VBoxContainer/HostButton
@onready var join_button = $VBoxContainer/JoinButton
@onready var back_button = $VBoxContainer/BackButton
@onready var address_line_edit = $VBoxContainer/AddressLineEdit

func _ready():
	# Use callable() to create callables for each signal method
	host_button.connect("pressed", Callable(self, "_on_HostButton_pressed"))
	join_button.connect("pressed", Callable(self, "_on_JoinButton_pressed"))
	back_button.connect("pressed", Callable(self, "_on_BackButton_pressed"))

	# Optional default for the IP field:
	address_line_edit.text = "192.168.0.24"  # Example default IP address


# ---------------------------
#    HOST BUTTON PRESSED
# ---------------------------
func _on_HostButton_pressed():
	# Create an ENet server so others can join.
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(SERVER_PORT, MAX_CLIENTS)
	if err != OK:
		push_error("Could not start server on port: %d!" % SERVER_PORT)
		return
	
	# Use get_multiplayer() to access the MultiplayerAPI
	var multiplayer_api = get_tree().get_multiplayer()
	multiplayer_api.multiplayer_peer = peer
	print("✅ Hosting server on port: %s" % SERVER_PORT)
	
	# Connect signals using callable() via get_multiplayer()
	multiplayer_api.connect("network_peer_connected", Callable(self, "_on_peer_connected"))
	multiplayer_api.connect("network_peer_disconnected", Callable(self, "_on_peer_disconnected"))
	
	# Change immediately to your main game scene
	get_tree().change_scene_to_file("res://Scenes/Main.tscn")

func _on_peer_connected(peer_id: int) -> void:
	print("✅ Peer with ID %d connected." % peer_id)
	# Optionally, show a list of all current peer IDs:
	var peers = get_tree().get_multiplayer().get_peer_ids()
	print("Current connected peers: ", peers)

func _on_peer_disconnected(id: int):
	print("Player with ID %d disconnected." % id)
	# Clean up data as needed

# ---------------------------
#    JOIN BUTTON PRESSED
# ---------------------------
func _on_JoinButton_pressed():
	# Connect to a host/server using the IP from our AddressLineEdit
	var ip_address = address_line_edit.text.strip_edges()
	if ip_address == "":
		push_error("Please enter a valid IP address!")
		return
	
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip_address, SERVER_PORT)
	if err != OK:
		push_error("Connection to %s:%d failed!" % [ip_address, SERVER_PORT])
		return
	
	# Set the multiplayer peer via get_multiplayer()
	var multiplayer_api = get_tree().get_multiplayer()
	multiplayer_api.multiplayer_peer = peer
	print("Connecting to server at %s:%d" % [ip_address, SERVER_PORT])
	
	# Connect signals to handle connection success and failure with callable()
	multiplayer_api.connect("connection_failed", Callable(self, "_on_connection_failed"))
	multiplayer_api.connect("connected_to_server", Callable(self, "_on_connected_to_server"))

func _on_connection_failed():
	print("❌ Connection failed!")
	# You could show a label or pop-up to the user here.

func _on_connected_to_server() -> void:
	print("✅ Successfully connected to the host!")
	print("Connected peers: ", get_tree().get_multiplayer().get_peers())

# ---------------------------
#    BACK BUTTON PRESSED
# ---------------------------
func _on_BackButton_pressed():
	# Go back to your title screen, or close the lobby.
	# For instance:
	print("Returning to the previous scene/menu...")
	get_tree().change_scene_to_file("res://Scenes/TitleScreen.tscn")
