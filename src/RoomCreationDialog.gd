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

# Available gamemodes (matching actual gamemode names from Gamemode*.gd files)
const GAMEMODES: Array[String] = [
	"Deathmatch",
	"Team Deathmatch",
	"Balls!!!",
	"Team Balls!!!",
	"Hide & Seek",
	"Capture",
	"Team Capture",
	"Race",
	"Team Race",
	"Home Run",
	"Team Home Run",
	"One vs. All"
]

var available_maps: Array = []
var is_creating: bool = false
var is_loading_maps: bool = false
@export var backend_path: NodePath = NodePath("../GlobalPlayMenu/Backend")
var backend: GlobalPlayMenuBackend

@onready var gamemode_dropdown: OptionButton = $VBoxContainer/GamemodeContainer/GamemodeDropdown
@onready var map_list: MapList = $VBoxContainer/MapList
@onready var max_players_spin: SpinBox = $VBoxContainer/MaxPlayersContainer/MaxPlayersSpin
@onready var public_toggle: CheckButton = $VBoxContainer/PublicContainer/PublicToggle
@onready var create_button: Button = $VBoxContainer/ButtonContainer/CreateButton
@onready var cancel_button: Button = $VBoxContainer/ButtonContainer/CancelButton
@onready var status_label: Label = $VBoxContainer/StatusLabel

# HTTP request for fetching worlds
var _http_worlds: HTTPRequest

func _ready() -> void:
	print("[RoomCreation] Dialog initializing...")
	# Resolve backend via exported path
	backend = get_node_or_null(backend_path) as GlobalPlayMenuBackend
	# Connect to backend
	if backend and backend.has_signal("room_created"):
		backend.room_created.connect(_on_backend_room_created)
		print("[RoomCreation] Backend room_created signal connected")

	# Setup HTTP request for worlds
	_http_worlds = HTTPRequest.new()
	add_child(_http_worlds)
	_http_worlds.request_completed.connect(_on_worlds_response)

	# Setup gamemode dropdown
	for gamemode: String in GAMEMODES:
		gamemode_dropdown.add_item(gamemode)
	gamemode_dropdown.select(0)
	print("[RoomCreation] Gamemode dropdown populated with ", GAMEMODES.size(), " options")

	# MapList will handle map selection via dedicated UI
	print("[RoomCreation] MapList initialized for map selection")

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

func fetch_available_maps() -> void:
	"""Fetch maps from worlds API"""
	if is_loading_maps:
		return

	is_loading_maps = true
	print("[RoomCreation] 📤 Fetching available maps from API...")

	var url := "http://localhost:30820/api/worlds"
	var headers: PackedStringArray = ["Content-Type: application/json"]

	var err := _http_worlds.request(url, headers)
	if err != OK:
		print("[RoomCreation] ❌ HTTP error:", err)
		is_loading_maps = false

func _on_worlds_response(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	print("[RoomCreation] 📥 Worlds response:", response_code, " result:", result)
	is_loading_maps = false

	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		print("[RoomCreation] ⚠️ Failed to fetch worlds, MapList will use local maps")
		return

	var json_text: String = body.get_string_from_utf8()
	var json := JSON.new()
	if json.parse(json_text) != OK:
		print("[RoomCreation] ❌ Failed to parse JSON")
		return

	var data := json.data as Dictionary
	var worlds: Array = data.get("worlds", []) as Array

	if worlds.size() == 0:
		print("[RoomCreation] ℹ️ No worlds found, MapList will use fallback maps")
		return

	print("[RoomCreation] ✅ Loaded worlds from API, MapList will display them")

func show_dialog() -> void:
	"""Show the room creation dialog"""
	print("[RoomCreation] Showing dialog...")
	visible = true
	is_creating = false
	create_button.disabled = false
	status_label.text = ""
	print("[RoomCreation] Dialog visible: true, MapList will handle map selection")

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
	var map_name: String = map_list.selected_name
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
