# Tinybox
# Copyright (C) 2023-present Caelan Douglas
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as
# published by the Free Software Foundation, either version 3 of the
# License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

extends MultiplayerPeer
class_name NodeBackendMultiplayerPeer

## Bridge between Node WebSocket backend and Godot's multiplayer system

signal node_peer_connected(peer_id: int)
signal node_peer_disconnected(peer_id: int)

var _local_peer_id: int = 0
var _connected_peers: PackedInt32Array = []
var _node_adapter: MultiplayerNodeAdapter
var _is_server: bool = false

func _init(node_adapter: MultiplayerNodeAdapter, local_peer_id: int, is_server: bool = false) -> void:
	_node_adapter = node_adapter
	_local_peer_id = local_peer_id
	_is_server = is_server
	_connected_peers = PackedInt32Array([local_peer_id])

	# Connect to Node adapter signals
	if _node_adapter:
		print("[NodePeer] 🔗 Connecting to Node adapter signals")

func close() -> void:
	"""Close the connection"""
	print("[NodePeer] 🔌 Closing Node backend multiplayer peer")
	_connected_peers.clear()
	_local_peer_id = 0

func add_peer(peer_id: int) -> void:
	"""Add a connected peer (called when peer joins)"""
	if not _connected_peers.has(peer_id):
		_connected_peers.append(peer_id)
		print("[NodePeer] ➕ Peer ", peer_id, " connected")
		peer_connected.emit(peer_id)

func remove_peer(peer_id: int) -> void:
	"""Remove a disconnected peer"""
	if _connected_peers.has(peer_id):
		_connected_peers.erase(peer_id)
		print("[NodePeer] ➖ Peer ", peer_id, " disconnected")
		peer_disconnected.emit(peer_id)

# MultiplayerPeer overrides

func send_bytes(data: PackedByteArray, targets: int = TRANSFER_MODE_RELIABLE, channel: int = 0) -> Error:
	"""Send raw bytes to peers (used by multiplayer system)"""
	# For now, not implementing direct byte transfer
	# RPC calls are handled through the higher-level system
	return OK

func get_packet() -> PackedByteArray:
	"""Get next packet (not used in this bridge)"""
	return PackedByteArray()

func get_available_packet_count() -> int:
	"""Get available packets (not used in this bridge)"""
	return 0

func get_unique_id() -> int:
	"""Get this peer's unique ID"""
	return _local_peer_id

func is_server() -> bool:
	"""Check if this peer is the server"""
	return _is_server

func is_connected_to_host() -> bool:
	"""Check if connected to host"""
	return _local_peer_id > 0

func get_connected_peers() -> PackedInt32Array:
	"""Get list of connected peer IDs"""
	return _connected_peers

func get_peers() -> PackedInt32Array:
	"""Get all peer IDs (including self)"""
	var all_peers = _connected_peers.duplicate()
	if not all_peers.has(_local_peer_id):
		all_peers.append(_local_peer_id)
	return all_peers

func is_peer_connected(peer: int) -> bool:
	"""Check if specific peer is connected"""
	return _connected_peers.has(peer)

func get_peer_tls_certificate(peer: int) -> TLSCertificate:
	"""Not applicable for WebSocket"""
	return null

func poll() -> int:
	"""Poll for incoming messages (handled async in Node adapter)"""
	return OK

# For multiplayer signal handling
func _on_peer_joined(peer_id: int, room_id: String) -> void:
	"""Called when a peer joins the room"""
	if peer_id != _local_peer_id:
		add_peer(peer_id)

func _on_peer_left(peer_id: int) -> void:
	"""Called when a peer leaves the room"""
	if peer_id != _local_peer_id:
		remove_peer(peer_id)
