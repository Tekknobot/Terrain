# NetworkManager.gd
extends Node

var multiplayer_api = null
var state_ready: bool = false   # This flag will signal when the game state is received.

func _ready():
	multiplayer_api = get_tree().get_multiplayer()

func host_game(port: int, max_clients: int) -> bool:
	var peer = ENetMultiplayerPeer.new()
	var err = peer.create_server(port, max_clients)
	if err != OK:
		push_error("Could not start server on port: %d!" % port)
		return false
	multiplayer_api.multiplayer_peer = peer
	print("✅ Hosting server on port: %d" % port)
	multiplayer_api.connect("peer_connected", Callable(self, "_on_peer_connected"))
	multiplayer_api.connect("peer_disconnected", Callable(self, "_on_peer_disconnected"))
	return true

func join_game(ip_address: String, port: int) -> bool:
	var peer = ENetMultiplayerPeer.new()
	var err = peer.create_client(ip_address, port)
	if err != OK:
		push_error("Connection to %s:%d failed!" % [ip_address, port])
		return false
	multiplayer_api.multiplayer_peer = peer
	print("Connecting to server at %s:%d" % [ip_address, port])
	multiplayer_api.connect("connection_failed", Callable(self, "_on_connection_failed"))
	multiplayer_api.connect("connected_to_server", Callable(self, "_on_connected_to_server"))
	return true

func _on_peer_connected(peer_id: int) -> void:
	print("✅ Peer connected with ID: %d" % peer_id)
	# When a new client connects, if the game state is stored, send it:
	if GameState.stored_map_data.size() > 0:
		rpc_id(peer_id, "receive_game_state", 
			GameState.stored_map_data,
			GameState.stored_unit_data,
			GameState.stored_structure_data)

func _on_peer_disconnected(peer_id: int) -> void:
	print("❌ Peer disconnected with ID: %d" % peer_id)

func _on_connection_failed() -> void:
	print("❌ Connection failed!")

func _on_connected_to_server() -> void:
	print("✅ Successfully connected to the host!")
	print("Connected peers: ", multiplayer_api.get_peers())
	# Wait a short delay to let the lobby finish processing and prepare for a scene change.
	await get_tree().create_timer(0.5).timeout  
	# Trigger a scene change on the client so that the main game scene loads.
	get_tree().change_scene_to_file("res://Scenes/Main.tscn")

@rpc
func receive_game_state(map_data: Dictionary, unit_data: Array, structure_data: Array) -> void:
	print("Game state successfully received on the client.")
	# Get a reference to the TileMap node in the current (client) main scene.
	var tile_map: Node = await wait_for_tilemap()
	if tile_map:
		tile_map._generate_client_map(map_data)
		tile_map.import_unit_data(unit_data)
		tile_map.import_structure_data(structure_data)
		tile_map.update_astar_grid()
		print("Client map and state rebuilt.")
	else:
		print("Error: Could not find the TileMap node in the current scene.")

# This function waits until the current scene has a TileMap node.
func wait_for_tilemap() -> Node:
	var tile_map: Node = null
	while tile_map == null:
		var current_scene = get_tree().get_current_scene()
		if current_scene and current_scene.has_node("TileMap"):
			tile_map = current_scene.get_node("TileMap")
		else:
			await get_tree().create_timer(0.1).timeout
	return tile_map
