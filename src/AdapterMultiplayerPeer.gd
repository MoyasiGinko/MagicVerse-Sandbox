# AdapterMultiplayerPeer - Wraps MultiplayerNodeAdapter to provide is_server() checks
# This is NOT a MultiplayerPeer extension, just a helper wrapper

class_name AdapterMultiplayerPeer

var _adapter: MultiplayerNodeAdapter

func _init(adapter: MultiplayerNodeAdapter) -> void:
	_adapter = adapter
	print("[AdapterPeer] Initialized with adapter")

func is_server() -> bool:
	if _adapter:
		return _adapter.is_server()
	return false

func get_unique_id() -> int:
	if _adapter:
		return _adapter.get_unique_peer_id()
	return 0
