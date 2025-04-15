# NetworkManager.gd

extends Node

# Port for the connection (choose an open port; 4242 is a common test port)
const SERVER_PORT = 4242
# Maximum number of connected clients (for your game two teams of eight units, adjust as needed)
const MAX_CLIENTS = 4

func _on_peer_connected(id):
	print("Peer connected with id: %d" % id)

func _on_peer_disconnected(id):
	print("Peer disconnected with id: %d" % id)

func connect_to_server(server_ip: String):
	var peer = ENetMultiplayerPeer.new()
	var err = peer.create_client(server_ip, SERVER_PORT)
	if err != OK:
		push_error("Failed to create client connection!")
		return
	get_tree().multiplayer.multiplayer_peer = peer
	print("Connecting to server at: %s:%d" % [server_ip, SERVER_PORT])
	# Optional: connect to signals to track connection progress
	get_tree().multiplayer.connect("connection_failed", self, "_on_connection_failed")
	get_tree().multiplayer.connect("connected_to_server", self, "_on_connected_to_server")
	
func _on_connection_failed():
	print("Connection to server failed!")
	
func _on_connected_to_server():
	print("Successfully connected to server!")
