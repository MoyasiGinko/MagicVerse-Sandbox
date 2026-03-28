extends RefCounted
class_name BackendConfig

const DEFAULT_DJANGO_BASE_URL := "http://127.0.0.1:8000"
const DEFAULT_NODE_API_BASE_URL := "http://127.0.0.1:30820/api"
const DEFAULT_NODE_WS_URL := "ws://127.0.0.1:30820"
const DEFAULT_WORLD_DATABASE_REPO := "https://tinybox-worlds.caelan-douglas.workers.dev/"
const DEFAULT_SERVER_LIST_URL := "https://raw.githubusercontent.com/MoyasiGinko/godot-world-release/refs/heads/main/server_list.json"
const DEFAULT_UPDATE_RELEASE_API_URL := "https://api.github.com/repos/caelan-douglas/tinybox/releases/latest"
const DEFAULT_UPDATE_RELEASE_PAGE_URL := "https://github.com/caelan-douglas/tinybox/releases/latest"

const PREF_SECTION := "backend"
const PREF_DJANGO_BASE_URL := "django_base_url"
const PREF_NODE_API_BASE_URL := "node_api_base_url"
const PREF_NODE_WS_URL := "node_ws_url"
const PREF_WORLD_DATABASE_REPO := "world_database_repo"
const PREF_SERVER_LIST_URL := "legacy_server_list_url"
const PREF_UPDATE_RELEASE_API_URL := "update_release_api_url"
const PREF_UPDATE_RELEASE_PAGE_URL := "update_release_page_url"
const PREF_SELECTED_SERVER_ID := "selected_server_id"

static func _trim_trailing_slash(url: String) -> String:
	var value := url.strip_edges()
	while value.ends_with("/"):
		value = value.left(value.length() - 1)
	return value

static func _normalize_local_loopback(url: String) -> String:
	# On some Windows setups, localhost adds ~200ms due IPv6 fallback; prefer IPv4 loopback.
	return url.replace("://localhost", "://127.0.0.1")

static func _load_url_pref(key: String, fallback: String) -> String:
	var saved: Variant = UserPreferences.load_pref(key, PREF_SECTION)
	if saved != null and str(saved).strip_edges() != "":
		return _normalize_local_loopback(_trim_trailing_slash(str(saved)))
	return fallback

static func _save_url_pref(key: String, value: Variant) -> void:
	var text := str(value).strip_edges()
	if text == "":
		return
	UserPreferences.save_pref(key, _trim_trailing_slash(text), PREF_SECTION)

static func get_django_base_url() -> String:
	return _load_url_pref(PREF_DJANGO_BASE_URL, DEFAULT_DJANGO_BASE_URL)

static func get_django_api_base_url() -> String:
	return get_django_base_url() + "/api"

static func get_client_config_url() -> String:
	return get_django_api_base_url() + "/client-config"

static func get_node_api_base_url() -> String:
	return _load_url_pref(PREF_NODE_API_BASE_URL, DEFAULT_NODE_API_BASE_URL)

static func get_node_ws_url() -> String:
	return _load_url_pref(PREF_NODE_WS_URL, DEFAULT_NODE_WS_URL)

static func get_world_database_repo() -> String:
	return _load_url_pref(PREF_WORLD_DATABASE_REPO, DEFAULT_WORLD_DATABASE_REPO)

static func get_legacy_server_list_url() -> String:
	return _load_url_pref(PREF_SERVER_LIST_URL, DEFAULT_SERVER_LIST_URL)

static func get_update_release_api_url() -> String:
	return _load_url_pref(PREF_UPDATE_RELEASE_API_URL, DEFAULT_UPDATE_RELEASE_API_URL)

static func get_update_release_page_url() -> String:
	return _load_url_pref(PREF_UPDATE_RELEASE_PAGE_URL, DEFAULT_UPDATE_RELEASE_PAGE_URL)

static func apply_client_config(config_values: Dictionary) -> void:
	if config_values.has(PREF_DJANGO_BASE_URL):
		_save_url_pref(PREF_DJANGO_BASE_URL, config_values.get(PREF_DJANGO_BASE_URL, ""))
	if config_values.has(PREF_NODE_API_BASE_URL):
		_save_url_pref(PREF_NODE_API_BASE_URL, config_values.get(PREF_NODE_API_BASE_URL, ""))
	if config_values.has(PREF_NODE_WS_URL):
		_save_url_pref(PREF_NODE_WS_URL, config_values.get(PREF_NODE_WS_URL, ""))
	if config_values.has(PREF_WORLD_DATABASE_REPO):
		_save_url_pref(PREF_WORLD_DATABASE_REPO, config_values.get(PREF_WORLD_DATABASE_REPO, ""))
	if config_values.has(PREF_SERVER_LIST_URL):
		_save_url_pref(PREF_SERVER_LIST_URL, config_values.get(PREF_SERVER_LIST_URL, ""))
	if config_values.has(PREF_UPDATE_RELEASE_API_URL):
		_save_url_pref(PREF_UPDATE_RELEASE_API_URL, config_values.get(PREF_UPDATE_RELEASE_API_URL, ""))
	if config_values.has(PREF_UPDATE_RELEASE_PAGE_URL):
		_save_url_pref(PREF_UPDATE_RELEASE_PAGE_URL, config_values.get(PREF_UPDATE_RELEASE_PAGE_URL, ""))
	if config_values.has(PREF_SELECTED_SERVER_ID):
		UserPreferences.save_pref(PREF_SELECTED_SERVER_ID, str(config_values.get(PREF_SELECTED_SERVER_ID, "")), PREF_SECTION)

static func set_selected_game_server(server_data: Dictionary) -> void:
	if server_data.has("id"):
		UserPreferences.save_pref(PREF_SELECTED_SERVER_ID, str(server_data.get("id", "")), PREF_SECTION)
	if server_data.has("api_url"):
		_save_url_pref(PREF_NODE_API_BASE_URL, server_data.get("api_url", ""))
	if server_data.has("ws_url"):
		_save_url_pref(PREF_NODE_WS_URL, server_data.get("ws_url", ""))

static func get_selected_server_id() -> String:
	var saved: Variant = UserPreferences.load_pref(PREF_SELECTED_SERVER_ID, PREF_SECTION)
	if saved == null:
		return ""
	return str(saved)
