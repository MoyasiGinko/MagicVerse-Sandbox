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

extends PanelContainer
class_name RoomCreationDialog

signal room_created(room_id: String, room_data: Dictionary)

# Available gamemodes
const GAMEMODES: Array[String] = [
	"Deathmatch",
	"Balls",
	"Hide & Seek",
	"King of the Hill",
	"Race",
	"Home Run",
	"1v1"
]

# Available maps
const MAPS: Array[String] = [
	"Default",
	"Arena",
	"Fortress",
	"Plaza"
]

var is_creating: bool = false
@export var backend_path: NodePath = NodePath("../GlobalPlayMenu/Backend")
var backend: GlobalPlayMenuBackend

@onready var gamemode_dropdown: OptionButton = $VBoxContainer/GamemodeContainer/GamemodeDropdown
@onready var map_dropdown: OptionButton = $VBoxContainer/MapContainer/MapDropdown
@onready var max_players_spin: SpinBox = $VBoxContainer/MaxPlayersContainer/MaxPlayersSpin
@onready var public_toggle: CheckButton = $VBoxContainer/PublicContainer/PublicToggle
@onready var create_button: Button = $VBoxContainer/ButtonContainer/CreateButton
@onready var cancel_button: Button = $VBoxContainer/ButtonContainer/CancelButton
@onready var status_label: Label = $VBoxContainer/StatusLabel

func _ready() -> void:
	print("[RoomCreation] Dialog initializing...")
	# Resolve backend via exported path
	backend = get_node_or_null(backend_path) as GlobalPlayMenuBackend
	# Connect to backend
	if backend and backend.has_signal("room_created"):
		backend.room_created.connect(_on_backend_room_created)
		print("[RoomCreation] Backend room_created signal connected")

	# Setup gamemode dropdown
	for gamemode: String in GAMEMODES:
		gamemode_dropdown.add_item(gamemode)
	gamemode_dropdown.select(0)
	print("[RoomCreation] Gamemode dropdown populated with ", GAMEMODES.size(), " options")

	# Setup map dropdown
	for map_name: String in MAPS:
		map_dropdown.add_item(map_name)
	map_dropdown.select(0)
	print("[RoomCreation] Map dropdown populated with ", MAPS.size(), " options")

	# Setup max players spinner
	max_players_spin.min_value = 2
	max_players_spin.max_value = 16
	max_players_spin.value = 8
	max_players_spin.step = 1
	print("[RoomCreation] Max players spinner set: min=2, max=16, default=8")

	# Setup toggle
	public_toggle.button_pressed = true
	print("[RoomCreation] Public toggle set to: true")

	# Connect buttons
	create_button.pressed.connect(_on_create_pressed)
	cancel_button.pressed.connect(_on_cancel_pressed)
	print("[RoomCreation] Button handlers connected")

	# Hide by default
	visible = false
	status_label.text = ""
	print("[RoomCreation] Dialog initialization complete!")
func show_dialog() -> void:
	"""Show the room creation dialog"""
	print("[RoomCreation] Showing dialog...")
	visible = true
	is_creating = false
	create_button.disabled = false
	status_label.text = ""
	print("[RoomCreation] Dialog visible: true, ready to create")

func hide_dialog() -> void:
	"""Hide the room creation dialog"""
	print("[RoomCreation] Hiding dialog...")
	visible = false
	print("[RoomCreation] Dialog visible: false")

func _on_create_pressed() -> void:
	"""Handle create button press"""
	print("[RoomCreation] === CREATE BUTTON PRESSED ===")
	if is_creating:
		print("[RoomCreation] ⚠️ Already creating a room, ignoring click")
		return

	if not Global.is_authenticated or Global.auth_token == "":
		print("[RoomCreation] ❌ Not authenticated! Token empty or user not logged in")
		status_label.text = "Not authenticated. Please login first."
		return

	var gamemode: String = gamemode_dropdown.get_item_text(gamemode_dropdown.get_selected_id())
	var map_name: String = map_dropdown.get_item_text(map_dropdown.get_selected_id())
	var max_players: int = int(max_players_spin.value)
	var is_public: bool = public_toggle.button_pressed

	print("[RoomCreation] ✓ User authenticated")
	print("[RoomCreation] Room settings:")
	print("[RoomCreation]   - Gamemode: ", gamemode)
	print("[RoomCreation]   - Map: ", map_name)
	print("[RoomCreation]   - Max Players: ", max_players)
	print("[RoomCreation]   - Public: ", is_public)

	is_creating = true
	create_button.disabled = true
	status_label.text = "Creating room..."
	print("[RoomCreation] 🔄 Sending creation request to backend...")
	var config: Dictionary = {
		"gamemode": gamemode,
		"mapName": map_name,
		"maxPlayers": max_players,
		"isPublic": is_public
	}
	if backend:
		backend.create_room(config)
	else:
		print("[RoomCreation] ❌ Backend not found; cannot create room")

func _send_room_creation_request(gamemode: String, map_name: String, max_players: int, is_public: bool) -> void:
	"""Deprecated: now routed through GlobalPlayMenuBackend"""
	var config: Dictionary = {
		"gamemode": gamemode,
		"mapName": map_name,
		"maxPlayers": max_players,
		"isPublic": is_public
	}
	if backend:
		backend.create_room(config)
	else:
		print("[RoomCreation] ❌ Backend not found; cannot create room")

func _on_backend_room_created(room_id: String, room_data: Dictionary) -> void:
	"""Handle room created via backend script"""
	is_creating = false
	create_button.disabled = false
	print("[RoomCreation] ✅ Room created successfully! ID: ", room_id)
	status_label.text = "Room created! Starting server..."
	room_created.emit(room_id, room_data)
	await get_tree().create_timer(1.0).timeout
	hide_dialog()

func _on_cancel_pressed() -> void:
	"""Handle cancel button press"""
	print("[RoomCreation] Cancel button pressed")
	if is_creating:
		print("[RoomCreation] ⚠️ Room creation in progress, ignoring cancel")
		return
	print("[RoomCreation] Closing dialog")
	hide_dialog()
