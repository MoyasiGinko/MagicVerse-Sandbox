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

extends ProgressBar
class_name GameTimer

var min_audio : AudioStreamPlayer
var end_audio : AudioStreamPlayer
@onready var anim : AnimationPlayer = $AnimationPlayer
var _node_sync_active: bool = false
var _authoritative_label: String = ""
var _last_server_time_s: float = -1.0
var _last_server_received_ms: int = 0
var _last_rendered_second: int = -1
var _local_end_ms: int = 0
var _last_predicted_time_s: float = -1.0

func _apply_timer_state(label: String, time_s: float) -> void:
	var timer_text : Label = get_node("Label")
	if timer_text != null:
		var mins := str(int(time_s as int / 60))
		var seconds := str('%02d' % (int(time_s as int) % 60))
		timer_text.text = str(label, " - ", mins, ":", seconds)
		value = time_s

	if (!min_audio.playing && !end_audio.playing):
		if round(time_s) == 60:
			min_audio.play()
			anim.play("flash_timer")
		elif round(time_s) == 10:
			end_audio.play()
			anim.play("flash_timer")

func _ready() -> void:
	min_audio = AudioStreamPlayer.new()
	end_audio = AudioStreamPlayer.new()
	min_audio.bus = "UI"
	end_audio.bus = "UI"
	min_audio.stream = load("res://data/audio/countdown.ogg")
	end_audio.stream = load("res://data/audio/countdown10sec.ogg")
	add_child(min_audio)
	add_child(end_audio)

func _process(_delta: float) -> void:
	if !_node_sync_active:
		return
	if _local_end_ms <= 0:
		return
	var now_ms: int = Time.get_ticks_msec()
	var predicted: float = maxf(0.0, float(_local_end_ms - now_ms) / 1000.0)
	# Keep countdown monotonic to avoid network jitter causing visual second regressions.
	if _last_predicted_time_s >= 0.0 and predicted > _last_predicted_time_s:
		predicted = _last_predicted_time_s
	_last_predicted_time_s = predicted
	var predicted_second: int = int(ceili(predicted))
	if predicted_second == _last_rendered_second:
		return
	_last_rendered_second = predicted_second
	_apply_timer_state(_authoritative_label, predicted)

@rpc("any_peer", "call_local", "reliable")
func update_timer(label : String, time_s : float) -> void:
	# only accept updates from server
	if multiplayer.get_remote_sender_id() != 1:
		return
	_node_sync_active = false
	_apply_timer_state(label, time_s)

func apply_timer_from_node(label: String, time_s: float, max_time: int = -1) -> void:
	if max_time > 0:
		max_value = max_time
	var now_ms: int = Time.get_ticks_msec()
	var clamped_time: float = maxf(0.0, time_s)
	var suggested_end_ms: int = now_ms + int(clamped_time * 1000.0)
	if _node_sync_active and _local_end_ms > 0:
		var local_remaining: float = maxf(0.0, float(_local_end_ms - now_ms) / 1000.0)
		var drift: float = clamped_time - local_remaining
		if drift < -0.15:
			# Server says less time remains; pull local clock forward.
			_local_end_ms = suggested_end_ms
			_last_rendered_second = -1
		elif drift > 2.5:
			# Large discrepancy likely means stale local anchor; hard resync.
			_local_end_ms = suggested_end_ms
			_last_rendered_second = -1
	else:
		_local_end_ms = suggested_end_ms
		_last_rendered_second = -1
	_node_sync_active = true
	_authoritative_label = label
	_last_server_time_s = clamped_time
	_last_server_received_ms = now_ms
	_last_predicted_time_s = maxf(0.0, float(_local_end_ms - now_ms) / 1000.0)
	_apply_timer_state(label, _last_predicted_time_s)

@rpc("any_peer", "call_local", "reliable")
func set_max_val_rpc(new : int) -> void:
	max_value = new
	value = new

@rpc("any_peer", "call_local", "reliable")
func set_visible_rpc(mode : bool) -> void:
	visible = mode
	if !mode:
		var timer_text: Label = get_node_or_null("Label")
		if timer_text != null:
			timer_text.text = ""
		_node_sync_active = false
		_authoritative_label = ""
		_last_server_time_s = -1.0
		_last_server_received_ms = 0
		_last_rendered_second = -1
		_local_end_ms = 0
		_last_predicted_time_s = -1.0
