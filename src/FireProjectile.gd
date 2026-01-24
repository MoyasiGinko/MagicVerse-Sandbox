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

extends SyncedRigidbody3D
class_name FireProjectile

# From Flamethrower

@onready var camera : Camera3D = get_viewport().get_camera_3d()
@onready var world : World = Global.get_world()

func _get_node_adapter() -> MultiplayerNodeAdapter:
	var root: Node = get_tree().root
	if root.has_meta("node_adapter"):
		return root.get_meta("node_adapter") as MultiplayerNodeAdapter
	for child: Node in root.get_children():
		if child.has_meta("node_adapter"):
			return child.get_meta("node_adapter") as MultiplayerNodeAdapter
	return null

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	$Area3D.connect("body_entered", _on_body_entered)
	despawn_time = 2.5
	super()

func _on_body_entered(body : Node3D) -> void:
	# only run on auth
	if !is_multiplayer_authority(): return

	if body.has_method("light_fire"):
		# special "from_who" arg for players
		if body is RigidPlayer:
			var from_id := get_multiplayer_authority()
			var adapter := _get_node_adapter()
			if adapter != null:
				adapter.send_rpc_call("remote_light_fire", [int(body.name), from_id, 8])
			body.light_fire(from_id, 8)
		# lower chance of lighting fire for anything that's not a player
		else:
			if (randi() % 10 > 8):
				body.light_fire.rpc()

@rpc("call_local")
func spawn_projectile(auth : int, shot_speed := 30) -> void:
	set_multiplayer_authority(auth)

	player_from = world.get_node_or_null(str(auth))

	# For Node.js backend: Check if player_from exists and is local player
	# For ENet: Check multiplayer authority
	var should_execute := false
	if player_from != null and player_from is RigidPlayer:
		should_execute = player_from.is_local_player
	else:
		should_execute = is_multiplayer_authority()

	if !should_execute: return

	# Position is already set by ShootTool.spawn_projectile() - do NOT override it
	# The position was passed via spawn_pos parameter and should be correct

	# determine direction from camera
	var direction := Vector3.ZERO
	if camera:
		direction = -camera.global_transform.basis.z
	# set own velocity
	linear_velocity = direction * shot_speed
