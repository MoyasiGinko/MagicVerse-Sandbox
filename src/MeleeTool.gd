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

extends Tool
class_name MeleeTool

enum MeleeType {
	BAT
}

@export var tool_name := "Bat"
@export var _melee_type : MeleeType = MeleeType.BAT
@export var damage : int = 4
@export var cooldown : int = 7
var knockback : int = 0
var cooldown_counter : int = 0
var deflect_time := 0
var is_hitting := false

var hit_area : Area3D = null
var large_hit_area : Area3D = null

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	super.init(tool_name, get_parent().get_parent() as RigidPlayer)

func add_visual_mesh_instance() -> void:
	visual_mesh_instance = visual_mesh.instantiate()
	tool_visual.add_child(visual_mesh_instance)
	hit_area = visual_mesh_instance.get_node_or_null("mesh/HitArea")
	if hit_area:
		hit_area.connect("body_entered", on_hit)
	large_hit_area = visual_mesh_instance.get_node_or_null("mesh/LargeHitArea")
	if large_hit_area:
		large_hit_area.connect("body_entered", on_large_hit)

func _physics_process(delta : float) -> void:
	# only execute on yourself
	if !_is_local_authority(): return
	# if this tool is selected
	if get_tool_active():
		if cooldown_counter <= 0:
			if Input.is_action_pressed("click"):
				# Limit the speed at which we can hit
				cooldown_counter = cooldown
				swing.rpc()
	cooldown_counter -= 1
	if deflect_time > 0:
		deflect_time -= 1

@rpc("call_local")
func swing() -> void:
	if visual_mesh_instance != null:
		# we must get it here because the visual mesh instance changes
		var animator : AnimationPlayer = visual_mesh_instance.get_node_or_null("AnimationPlayer")
		if animator:
			animator.play("hit")
		is_hitting = true
		await get_tree().create_timer(0.2).timeout
		is_hitting = false

func on_hit(body : Node3D) -> void:
	if !self.is_inside_tree(): return
	# reduce player health on hit
	if body is RigidPlayer:
		var body_player : RigidPlayer = body as RigidPlayer
		# Don't hit ourselves
		if _do_we_own_player(body_player):
			return

		# only take damage if not tripped
		if multiplayer.is_server():
			if body_player._state != RigidPlayer.TRIPPED:
				var executor_id : int = _get_tool_owner_peer_id()
				body_player.reduce_health(damage, RigidPlayer.CauseOfDeath.MELEE, executor_id)
				body_player.change_state.rpc_id(body_player.get_multiplayer_authority(), RigidPlayer.TRIPPED)
				# running as server
				body_player.emit_signal("hit_by_melee", self)
		# only run this on the authority of who was hit (not necessarily the authority of the tool)
		elif body_player.is_local_player:
			# running as hit player's authority
			body_player.emit_signal("hit_by_melee", self)
			# apply small impulse from bat hit
			body_player.apply_impulse(Vector3(randi_range(-2, 2), 5, randi_range(-2, 2)))
			# apply impulse from knockback (defaults zero, changed with modifiers)
			if knockback > 0:
				var knockback_vec : Vector3 = global_position.direction_to(body_player.global_position).normalized() * knockback
				knockback_vec.y = knockback * 0.5
				body_player.apply_impulse(knockback_vec)
			# we hit a player, set the player's last hit by ID to this one
			var executor_id : int = _get_tool_owner_peer_id()
			body_player.set_last_hit_by_id.rpc(executor_id)
	elif body is Character:
		body.set_health(body.get_health() - damage)
	# kick players out of seats
	elif body is MotorSeat:
		if body.controlling_player != null:
			# if it's someone else. don't kick ourselves out...
			var seat_player : RigidPlayer = body.controlling_player as RigidPlayer
			if seat_player != null and !_do_we_own_player(seat_player):
				seat_player.seat_destroyed.rpc_id(seat_player.get_multiplayer_authority(), true)
				body.set_controlling_player.rpc(-1)

func on_large_hit(body : Node3D) -> void:
	# only run on auth
	if !_is_local_authority(): return

	# Deflects rockets, bombs, balls, and other players.
	if (body is Rocket || body is Bomb || body is ClayBall) && deflect_time < 1 && is_hitting:
		if visual_mesh_instance != null:
			var deflect : AudioStreamPlayer3D = visual_mesh_instance.get_node_or_null("DeflectAudio")
			deflect_time = 40
			deflect.play()
		# deflect body on body's auth
		body.deflect.rpc_id(body.get_multiplayer_authority(), -tool_player_owner.global_transform.basis.z)
