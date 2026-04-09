extends PanelContainer
class_name StatsMenu

signal closed

@onready var hub: VBoxContainer = $Margin/VBox/Content/Hub
@onready var leaderboards_screen: HBoxContainer = $Margin/VBox/Content/LeaderboardsScreen
@onready var match_history_screen: HBoxContainer = $Margin/VBox/Content/MatchHistoryScreen

@onready var leaderboards_status: Label = $Margin/VBox/Content/LeaderboardsScreen/Main/Status
@onready var leaderboard_rows: VBoxContainer = $Margin/VBox/Content/LeaderboardsScreen/Main/Scroll/Rows
@onready var match_history_status: Label = $Margin/VBox/Content/MatchHistoryScreen/Main/Status
@onready var match_history_rows: VBoxContainer = $Margin/VBox/Content/MatchHistoryScreen/Main/Scroll/Rows

var _http: HTTPRequest
var _request_kind: String = ""
var _request_scope: String = "global"
var _request_paths: Array[String] = []
var _request_index: int = 0
var _last_request_url: String = ""

const STATS_DEBUG_LOGGING := true

func _debug_log(message: String) -> void:
	if STATS_DEBUG_LOGGING:
		print("[StatsMenu] ", message)

func _ready() -> void:
	visible = false
	$Margin/VBox/Header/CloseButton.pressed.connect(_emit_close)
	$Margin/VBox/Content/Hub/Buttons/LeaderboardsButton.pressed.connect(_open_leaderboards)
	$Margin/VBox/Content/Hub/Buttons/MatchHistoryButton.pressed.connect(_open_match_history)

	$Margin/VBox/Content/LeaderboardsScreen/Sidebar/SidebarVBox/GlobalButton.pressed.connect(_load_leaderboards.bind("global"))
	$Margin/VBox/Content/LeaderboardsScreen/Sidebar/SidebarVBox/UpcomingButton.pressed.connect(_load_leaderboards.bind("ranked"))
	$Margin/VBox/Content/LeaderboardsScreen/Sidebar/SidebarVBox/BackButton.pressed.connect(_show_hub)

	$Margin/VBox/Content/MatchHistoryScreen/Sidebar/SidebarVBox/GlobalButton.pressed.connect(_load_match_history.bind("global"))
	$Margin/VBox/Content/MatchHistoryScreen/Sidebar/SidebarVBox/UpcomingButton.pressed.connect(_load_match_history.bind("ranked"))
	$Margin/VBox/Content/MatchHistoryScreen/Sidebar/SidebarVBox/BackButton.pressed.connect(_show_hub)

	_http = HTTPRequest.new()
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)

func open_menu() -> void:
	visible = true
	_show_hub()

func _emit_close() -> void:
	emit_signal("closed")

func _show_hub() -> void:
	hub.visible = true
	leaderboards_screen.visible = false
	match_history_screen.visible = false

func _open_leaderboards() -> void:
	hub.visible = false
	leaderboards_screen.visible = true
	match_history_screen.visible = false
	_load_leaderboards("global")

func _open_match_history() -> void:
	hub.visible = false
	leaderboards_screen.visible = false
	match_history_screen.visible = true
	_load_match_history("global")

func _normalize_base_url(url: String) -> String:
	var value := url.strip_edges()
	while value.ends_with("/"):
		value = value.left(value.length() - 1)
	return value

func _build_request_url(path: String, scope: String, base: String) -> String:
	var resolved_path := path
	if resolved_path.begins_with("http://") or resolved_path.begins_with("https://"):
		var abs_separator := "?" if resolved_path.find("?") == -1 else "&"
		return "%s%sscope=%s" % [resolved_path, abs_separator, scope]
	var separator := "?" if resolved_path.find("?") == -1 else "&"
	return "%s%s%sscope=%s" % [base, resolved_path, separator, scope]

func _request_json(paths: Array[String], scope: String, kind: String) -> void:
	if _http.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		_debug_log("Request skipped; HTTPRequest is busy")
		return

	_request_kind = kind
	_request_scope = scope
	_request_paths.clear()
	for path in paths:
		if path.strip_edges() != "":
			_request_paths.append(path)
	_request_index = 0
	if _request_paths.is_empty():
		_show_request_error(kind, "No endpoint configured")
		return

	var base := _normalize_base_url(BackendConfig.get_django_api_base_url())
	var url := _build_request_url(_request_paths[_request_index], scope, base)
	_last_request_url = url
	_debug_log("Starting %s request scope=%s url=%s" % [kind, scope, url])
	var headers: PackedStringArray = ["Content-Type: application/json"]
	if Global.is_authenticated and Global.auth_token != "":
		headers.append("Authorization: Bearer " + Global.auth_token)

	var err := _http.request(url, headers)
	if err != OK:
		_debug_log("Request start failed err=%d url=%s" % [err, url])
		_show_request_error(kind, "Failed to start request")

func _retry_next_endpoint() -> bool:
	if _request_index + 1 >= _request_paths.size():
		return false
	if _http.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		return false

	_request_index += 1
	var base := _normalize_base_url(BackendConfig.get_django_api_base_url())
	var path := _request_paths[_request_index]
	var url := _build_request_url(path, _request_scope, base)
	_last_request_url = url
	_debug_log("Retrying %s request with fallback endpoint[%d]=%s" % [_request_kind, _request_index, url])
	var headers: PackedStringArray = ["Content-Type: application/json"]
	if Global.is_authenticated and Global.auth_token != "":
		headers.append("Authorization: Bearer " + Global.auth_token)
	var err := _http.request(url, headers)
	if err != OK:
		_debug_log("Fallback request start failed err=%d url=%s" % [err, url])
		return false
	return true

func _show_request_error(kind: String, message: String) -> void:
	if kind == "leaderboards":
		leaderboards_status.text = message
	else:
		match_history_status.text = message

func _load_leaderboards(scope: String) -> void:
	leaderboards_status.text = "Loading %s leaderboard..." % scope.capitalize()
	_clear_children(leaderboard_rows)
	_request_json([
		"/leaderboard?stat=kills&limit=100",
		"/leaderboards",
		"/stats/leaderboard",
	], scope, "leaderboards")

func _load_match_history(scope: String) -> void:
	match_history_status.text = "Loading %s match history..." % scope.capitalize()
	_clear_children(match_history_rows)
	_request_json([
		"/matches/history",
		"/matches",
		"/stats/matches",
		_normalize_base_url(BackendConfig.get_node_api_base_url()) + "/rooms/matches/history",
	], scope, "match_history")

func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var body_text := body.get_string_from_utf8()
	if body_text.length() > 280:
		body_text = body_text.substr(0, 280) + "..."
	_debug_log("Completed %s request url=%s result=%d response_code=%d body=%s" % [_request_kind, _last_request_url, result, response_code, body_text])

	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		if _retry_next_endpoint():
			return
		if _request_kind == "match_history" and response_code == 404:
			_show_request_error(
				_request_kind,
				"Match history endpoint is not available on this server (HTTP 404)",
			)
			return
		if _request_scope == "ranked":
			_show_request_error(_request_kind, "Ranked stats are coming soon")
		else:
			_show_request_error(_request_kind, "Unable to load data right now (HTTP %d)" % response_code)
		return

	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		_debug_log("JSON parse failed for url=%s" % _last_request_url)
		if _retry_next_endpoint():
			return
		_show_request_error(_request_kind, "Invalid server response")
		return

	if _request_kind == "leaderboards":
		_render_leaderboards(json.data)
	else:
		_render_match_history(json.data)

func _extract_entries(data: Variant) -> Array:
	if data is Array:
		return data as Array
	if data is Dictionary:
		var obj := data as Dictionary
		for key: String in ["results", "entries", "leaderboard", "users", "history", "matches", "data"]:
			var value: Variant = obj.get(key, null)
			if value is Array:
				return value as Array
	return []

func _to_int(value: Variant, fallback: int = 0) -> int:
	if value is int:
		return value as int
	if value is bool:
		return 1 if (value as bool) else 0
	if value is float:
		return floori(value as float)
	if value is String:
		var text := (value as String).strip_edges()
		if text.is_valid_int():
			return text.to_int()
		if text.is_valid_float():
			return floori(text.to_float())
	return fallback

func _to_float(value: Variant, fallback: float = 0.0) -> float:
	if value is float:
		return value as float
	if value is int:
		return float(value as int)
	if value is String:
		var text := (value as String).strip_edges()
		if text.is_valid_float():
			return text.to_float()
	return fallback

func _to_bool(value: Variant, fallback: bool = false) -> bool:
	if value is bool:
		return value as bool
	if value is int:
		return (value as int) != 0
	if value is float:
		return absf(value as float) > 0.00001
	if value is String:
		var text := (value as String).strip_edges().to_lower()
		if text == "true" or text == "1" or text == "yes":
			return true
		if text == "false" or text == "0" or text == "no":
			return false
	return fallback

func _render_leaderboards(data: Variant) -> void:
	_clear_children(leaderboard_rows)
	var entries := _extract_entries(data)
	if entries.is_empty():
		leaderboards_status.text = "No leaderboard entries yet"
		return

	leaderboards_status.text = "Loaded %d players" % entries.size()
	_add_leaderboard_row(["#", "Player", "Rating", "Wins", "Losses", "Kills", "Deaths", "K/D", "Matches"], true)

	var rank := 1
	for value: Variant in entries:
		if not (value is Dictionary):
			continue
		var entry := value as Dictionary
		var name := str(entry.get("display_name", entry.get("username", entry.get("player_name", "Unknown"))))
		var wins := _to_int(entry.get("wins", 0), 0)
		var losses := _to_int(entry.get("losses", 0), 0)
		var kills := _to_int(entry.get("kills", 0), 0)
		var deaths := _to_int(entry.get("deaths", 0), 0)
		var matches := _to_int(entry.get("matches", entry.get("matches_played", wins + losses)), wins + losses)
		var rating := _to_int(entry.get("rating", entry.get("score", entry.get("stat_value", 0))), 0)
		var kdr := 0.0 if deaths <= 0 else float(kills) / float(deaths)
		var row_rank := _to_int(entry.get("rank", rank), rank)
		_add_leaderboard_row([
			str(row_rank),
			name,
			str(rating),
			str(wins),
			str(losses),
			str(kills),
			str(deaths),
			"%.2f" % kdr,
			str(matches)
		], false)
		rank += 1

func _add_leaderboard_row(values: Array, is_header: bool) -> void:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.custom_minimum_size = Vector2(0, 34 if is_header else 30)

	var bg := ColorRect.new()
	bg.color = Color(0.17, 0.22, 0.31, 0.65 if is_header else 0.35)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.add_child(bg)
	row.move_child(bg, 0)

	var grid := GridContainer.new()
	grid.columns = 9
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 3)
	row.add_child(grid)

	for i: int in values.size():
		var label := Label.new()
		label.text = str(values[i])
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if i == 1 else HORIZONTAL_ALIGNMENT_CENTER
		if is_header:
			label.add_theme_color_override("font_color", Color(0.83, 0.94, 1.0, 1.0))
		else:
			label.add_theme_color_override("font_color", Color(0.95, 0.96, 1.0, 0.94))
		grid.add_child(label)

	leaderboard_rows.add_child(row)

func _render_match_history(data: Variant) -> void:
	_clear_children(match_history_rows)
	var entries := _extract_entries(data)
	if entries.is_empty():
		match_history_status.text = "No match history entries yet"
		return

	match_history_status.text = "Loaded %d matches" % entries.size()
	for value: Variant in entries:
		if not (value is Dictionary):
			continue
		var entry := value as Dictionary
		var card := PanelContainer.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var body := VBoxContainer.new()
		body.add_theme_constant_override("separation", 4)
		card.add_child(body)

		var title := Label.new()
		var match_id := str(entry.get("id", entry.get("match_id", "-")))
		var gamemode := str(entry.get("gamemode", "Unknown"))
		title.text = "Match %s - %s" % [match_id, gamemode]
		title.add_theme_color_override("font_color", Color(0.86, 0.95, 1.0, 1.0))
		body.add_child(title)

		var winner_type := str(entry.get("winner_type", "")).strip_edges().to_lower()
		var is_draw := _to_bool(entry.get("is_draw", winner_type == "draw"), winner_type == "draw")
		var winner := "Draw" if is_draw else str(entry.get("winner_name", entry.get("winner", "Unknown")))
		var duration := _to_int(entry.get("duration_seconds", 0), 0)
		var started_ms := _to_int(entry.get("game_started_at_ms", 0), 0)
		var ended_ms := _to_int(entry.get("game_ended_at_ms", 0), 0)
		var created := str(entry.get("created_at", entry.get("created", "")))
		var start_text := _format_match_datetime(started_ms, created)
		var end_text := _format_match_datetime(ended_ms, created)
		var outcome := "Draw"
		if not is_draw:
			if winner_type == "team":
				outcome = "Team %s won" % winner
			else:
				outcome = "%s won" % winner
		var details := Label.new()
		details.text = "Outcome: %s   Duration: %s" % [outcome, _format_duration(duration)]
		details.add_theme_color_override("font_color", Color(0.83, 0.9, 0.95, 0.9))
		body.add_child(details)

		var timing := Label.new()
		timing.text = "Started: %s   Ended: %s" % [start_text, end_text]
		timing.add_theme_color_override("font_color", Color(0.72, 0.84, 0.95, 0.88))
		body.add_child(timing)

		var mvp_value: Variant = entry.get("mvp", null)
		if mvp_value is Dictionary:
			var mvp := mvp_value as Dictionary
			var mvp_name := str(mvp.get("display_name", mvp.get("username", "Unknown")))
			var mvp_score := _to_int(mvp.get("score", mvp.get("kills", 0)), 0)
			var mvp_k := _to_int(mvp.get("kills", 0), 0)
			var mvp_d := _to_int(mvp.get("deaths", 0), 0)
			var mvp_line := Label.new()
			mvp_line.text = "MVP: %s   Score: %d   K/D: %d/%d" % [mvp_name, mvp_score, mvp_k, mvp_d]
			mvp_line.add_theme_color_override("font_color", Color(0.95, 0.84, 0.62, 0.95))
			body.add_child(mvp_line)

		var participants_value: Variant = entry.get("players", entry.get("participants", []))
		if participants_value is Array and not (participants_value as Array).is_empty():
			var participants := participants_value as Array
			var teams_value: Variant = entry.get("teams", null)
			if teams_value is Dictionary and (teams_value as Dictionary).size() > 0:
				var teams := teams_value as Dictionary
				for team_key_value: Variant in teams.keys():
					var team_key := str(team_key_value)
					var team_players_value: Variant = teams.get(team_key, [])
					if not (team_players_value is Array):
						continue
					var team_players := team_players_value as Array
					var team_line := Label.new()
					var player_parts: Array[String] = []
					for player_value: Variant in team_players:
						if not (player_value is Dictionary):
							continue
						var player := player_value as Dictionary
						var pname := str(player.get("display_name", player.get("username", "Player")))
						var pscore := _to_int(player.get("score", player.get("kills", 0)), 0)
						var pk := _to_int(player.get("kills", 0), 0)
						var pd := _to_int(player.get("deaths", 0), 0)
						player_parts.append("%s %d pts (%d/%d)" % [pname, pscore, pk, pd])
					team_line.text = "%s: %s" % [team_key, ", ".join(player_parts)]
					team_line.add_theme_color_override("font_color", Color(0.75, 0.86, 0.96, 0.85))
					body.add_child(team_line)
			else:
				var players_line := Label.new()
				var player_parts: Array[String] = []
				for participant_value: Variant in participants:
					if not (participant_value is Dictionary):
						continue
					var participant := participant_value as Dictionary
					var pname := str(participant.get("display_name", participant.get("username", "Player")))
					var pscore := _to_int(participant.get("score", participant.get("kills", 0)), 0)
					var pk := _to_int(participant.get("kills", 0), 0)
					var pd := _to_int(participant.get("deaths", 0), 0)
					player_parts.append("%s %d pts (%d/%d)" % [pname, pscore, pk, pd])
				players_line.text = "Players: " + ", ".join(player_parts)
				players_line.add_theme_color_override("font_color", Color(0.75, 0.86, 0.96, 0.85))
				body.add_child(players_line)

		match_history_rows.add_child(card)

func _format_duration(seconds_total: int) -> String:
	var safe_seconds := maxi(0, seconds_total)
	var hours := safe_seconds / 3600
	var mins := (safe_seconds % 3600) / 60
	var secs := safe_seconds % 60
	if hours > 0:
		return "%dh %02dm %02ds" % [hours, mins, secs]
	if mins > 0:
		return "%dm %02ds" % [mins, secs]
	return "%ds" % secs

func _format_match_datetime(unix_ms: int, fallback: String) -> String:
	if unix_ms <= 0:
		return fallback if fallback != "" else "N/A"
	var unix_s := floori(float(unix_ms) / 1000.0)
	var dt := Time.get_datetime_dict_from_unix_time(unix_s)
	if dt.is_empty():
		return fallback if fallback != "" else "N/A"
	return "%04d-%02d-%02d %02d:%02d:%02d" % [
		_to_int(dt.get("year", 0), 0),
		_to_int(dt.get("month", 0), 0),
		_to_int(dt.get("day", 0), 0),
		_to_int(dt.get("hour", 0), 0),
		_to_int(dt.get("minute", 0), 0),
		_to_int(dt.get("second", 0), 0),
	]

func _clear_children(node: Node) -> void:
	for child in node.get_children():
		child.queue_free()
