extends RefCounted
class_name BackendConfig

const DEFAULT_DJANGO_BASE_URL := "http://127.0.0.1:8000"
const DEFAULT_NODE_API_BASE_URL := "http://127.0.0.1:30820/api"
const DEFAULT_NODE_WS_URL := "ws://127.0.0.1:30820"

const PREF_SECTION := "backend"
const PREF_DJANGO_BASE_URL := "django_base_url"
const PREF_NODE_API_BASE_URL := "node_api_base_url"
const PREF_NODE_WS_URL := "node_ws_url"
const PREF_SELECTED_SERVER_ID := "selected_server_id"

static func _trim_trailing_slash(url: String) -> String:
	var value := url.strip_edges()
	while value.ends_with("/"):
		value = value.left(value.length() - 1)
	return value

static func _normalize_local_loopback(url: String) -> String:
	# On some Windows setups, localhost adds ~200ms due IPv6 fallback; prefer IPv4 loopback.
	return url.replace("://localhost", "://127.0.0.1")

static func get_django_base_url() -> String:
	var saved: Variant = UserPreferences.load_pref(PREF_DJANGO_BASE_URL, PREF_SECTION)
	if saved != null and str(saved).strip_edges() != "":
		return _normalize_local_loopback(_trim_trailing_slash(str(saved)))
	return DEFAULT_DJANGO_BASE_URL

static func get_django_api_base_url() -> String:
	return get_django_base_url() + "/api"

static func get_node_api_base_url() -> String:
	var saved: Variant = UserPreferences.load_pref(PREF_NODE_API_BASE_URL, PREF_SECTION)
	if saved != null and str(saved).strip_edges() != "":
		return _normalize_local_loopback(_trim_trailing_slash(str(saved)))
	return DEFAULT_NODE_API_BASE_URL

static func get_node_ws_url() -> String:
	var saved: Variant = UserPreferences.load_pref(PREF_NODE_WS_URL, PREF_SECTION)
	if saved != null and str(saved).strip_edges() != "":
		return _normalize_local_loopback(_trim_trailing_slash(str(saved)))
	return DEFAULT_NODE_WS_URL

static func set_selected_game_server(server_data: Dictionary) -> void:
	if server_data.has("id"):
		UserPreferences.save_pref(PREF_SELECTED_SERVER_ID, str(server_data.get("id", "")), PREF_SECTION)
	if server_data.has("api_url"):
		UserPreferences.save_pref(PREF_NODE_API_BASE_URL, _trim_trailing_slash(str(server_data.get("api_url", ""))), PREF_SECTION)
	if server_data.has("ws_url"):
		UserPreferences.save_pref(PREF_NODE_WS_URL, _trim_trailing_slash(str(server_data.get("ws_url", ""))), PREF_SECTION)

static func get_selected_server_id() -> String:
	var saved: Variant = UserPreferences.load_pref(PREF_SELECTED_SERVER_ID, PREF_SECTION)
	if saved == null:
		return ""
	return str(saved)
