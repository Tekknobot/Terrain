# NetworkTester.gd
extends Node

func _ready():
	var mp = get_tree().get_multiplayer()
	print("👤 My peer ID:", mp.get_unique_id(),
		  "  Authority peer ID:", get_multiplayer_authority(),
		  "  Am I authority?", is_multiplayer_authority())

# ——— Host RPC ———
# Now callable by any peer (not just authority), but we guard inside:
@rpc("any_peer", "reliable")
func ping(from_id: int) -> void:
	if not is_multiplayer_authority():
		return
	print("🏠 Host received PING from peer", from_id)
	# reply back
	rpc_id(from_id, "pong", get_multiplayer_authority())

# ——— Client+Host RPC ———
@rpc("any_peer")
func pong(from_id: int) -> void:
	print("🔔 Peer", get_tree().get_multiplayer().get_unique_id(),
		  "got PONG from", from_id)

func _input(event):
	if event.is_action_pressed("ui_accept") and not is_multiplayer_authority():
		var auth_id = get_multiplayer_authority()
		print("Client sending PING to authority peer", auth_id)
		rpc_id(auth_id, "ping", get_tree().get_multiplayer().get_unique_id())
