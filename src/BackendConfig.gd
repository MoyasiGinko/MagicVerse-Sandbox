extends RefCounted
class_name BackendConfig

const ENV_LOCAL := "local"
const ENV_PRODUCTION := "production"

# Toggle this to switch between local and production credentials.
const ACTIVE_ENV := ENV_PRODUCTION

const LOCAL_DJANGO_BASE_URL := "http://127.0.0.1:8000"
const LOCAL_NODE_API_BASE_URL := "http://127.0.0.1:30820/api"
const LOCAL_NODE_WS_URL := "ws://127.0.0.1:30820"
const LOCAL_WORLD_DATABASE_REPO := "https://tinybox-worlds.caelan-douglas.workers.dev/"
const LOCAL_SERVER_LIST_URL := "https://raw.githubusercontent.com/MoyasiGinko/godot-world-release/refs/heads/main/server_list.json"
const LOCAL_UPDATE_RELEASE_API_URL := "https://api.github.com/repos/caelan-douglas/tinybox/releases/latest"
const LOCAL_UPDATE_RELEASE_PAGE_URL := "https://github.com/caelan-douglas/tinybox/releases/latest"

const PROD_DJANGO_BASE_URL := "https://sandbox-world-server-asbqp.eu-east-1.migetapp.com"
const PROD_NODE_API_BASE_URL := "https://sandbox-multiplayer-server-frmbi.eu-east-1.migetapp.com/api"
const PROD_NODE_WS_URL := "wss://sandbox-multiplayer-server-frmbi.eu-east-1.migetapp.com"
const PROD_WORLD_DATABASE_REPO := "https://tinybox-worlds.caelan-douglas.workers.dev/"
const PROD_SERVER_LIST_URL := "https://raw.githubusercontent.com/MoyasiGinko/godot-world-release/refs/heads/main/server_list.json"
const PROD_UPDATE_RELEASE_API_URL := "https://api.github.com/repos/caelan-douglas/tinybox/releases/latest"
const PROD_UPDATE_RELEASE_PAGE_URL := "https://github.com/caelan-douglas/tinybox/releases/latest"

const DEFAULT_DJANGO_BASE_URL := PROD_DJANGO_BASE_URL if ACTIVE_ENV == ENV_PRODUCTION else LOCAL_DJANGO_BASE_URL
const DEFAULT_NODE_API_BASE_URL := PROD_NODE_API_BASE_URL if ACTIVE_ENV == ENV_PRODUCTION else LOCAL_NODE_API_BASE_URL
const DEFAULT_NODE_WS_URL := PROD_NODE_WS_URL if ACTIVE_ENV == ENV_PRODUCTION else LOCAL_NODE_WS_URL
const DEFAULT_WORLD_DATABASE_REPO := PROD_WORLD_DATABASE_REPO if ACTIVE_ENV == ENV_PRODUCTION else LOCAL_WORLD_DATABASE_REPO
const DEFAULT_SERVER_LIST_URL := PROD_SERVER_LIST_URL if ACTIVE_ENV == ENV_PRODUCTION else LOCAL_SERVER_LIST_URL
const DEFAULT_UPDATE_RELEASE_API_URL := PROD_UPDATE_RELEASE_API_URL if ACTIVE_ENV == ENV_PRODUCTION else LOCAL_UPDATE_RELEASE_API_URL
const DEFAULT_UPDATE_RELEASE_PAGE_URL := PROD_UPDATE_RELEASE_PAGE_URL if ACTIVE_ENV == ENV_PRODUCTION else LOCAL_UPDATE_RELEASE_PAGE_URL

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

static func _is_loopback_url(url: String) -> bool:
	var normalized := _normalize_local_loopback(url).to_lower()
	return normalized.begins_with("http://127.0.0.1") \
		or normalized.begins_with("https://127.0.0.1") \
		or normalized.begins_with("ws://127.0.0.1") \
		or normalized.begins_with("wss://127.0.0.1")

static func _is_protected_remote_key(key: String) -> bool:
	return key == PREF_DJANGO_BASE_URL or key == PREF_NODE_API_BASE_URL or key == PREF_NODE_WS_URL

static func _default_for_key(key: String) -> String:
	if key == PREF_DJANGO_BASE_URL:
		return DEFAULT_DJANGO_BASE_URL
	if key == PREF_NODE_API_BASE_URL:
		return DEFAULT_NODE_API_BASE_URL
	if key == PREF_NODE_WS_URL:
		return DEFAULT_NODE_WS_URL
	if key == PREF_WORLD_DATABASE_REPO:
		return DEFAULT_WORLD_DATABASE_REPO
	if key == PREF_SERVER_LIST_URL:
		return DEFAULT_SERVER_LIST_URL
	if key == PREF_UPDATE_RELEASE_API_URL:
		return DEFAULT_UPDATE_RELEASE_API_URL
	if key == PREF_UPDATE_RELEASE_PAGE_URL:
		return DEFAULT_UPDATE_RELEASE_PAGE_URL
	return ""

static func _sanitize_remote_value(key: String, value: String) -> String:
	var normalized := _normalize_local_loopback(_trim_trailing_slash(value))
	if _is_protected_remote_key(key) and _is_loopback_url(normalized):
		var fallback := _default_for_key(key)
		if fallback != "" and not _is_loopback_url(fallback):
			return fallback
	return normalized

static func _load_pref_safe(key: String, section: String) -> Variant:
	# During startup, UserPreferences autoload may not be ready yet.
	if UserPreferences != null and UserPreferences.has_method("load_pref"):
		return UserPreferences.load_pref(key, section)

	var config := ConfigFile.new()
	var err := config.load("user://preferences.txt")
	if err != OK:
		return null
	if config.has_section_key(section, key):
		return config.get_value(section, key, null)
	return null

static func _save_pref_safe(key: String, value: Variant, section: String) -> void:
	# During startup, UserPreferences autoload may not be ready yet.
	if UserPreferences != null and UserPreferences.has_method("save_pref"):
		UserPreferences.save_pref(key, value, section)
		return

	var config := ConfigFile.new()
	var err := config.load("user://preferences.txt")
	if err != OK:
		config = ConfigFile.new()
	config.set_value(section, key, value)
	config.save("user://preferences.txt")

static func _load_url_pref(key: String, fallback: String) -> String:
	var saved: Variant = _load_pref_safe(key, PREF_SECTION)
	if saved != null and str(saved).strip_edges() != "":
		return _sanitize_remote_value(key, str(saved))
	return fallback

static func _save_url_pref(key: String, value: Variant) -> void:
	var text := str(value).strip_edges()
	if text == "":
		return
	_save_pref_safe(key, _sanitize_remote_value(key, text), PREF_SECTION)

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
		_save_pref_safe(PREF_SELECTED_SERVER_ID, str(config_values.get(PREF_SELECTED_SERVER_ID, "")), PREF_SECTION)

static func set_selected_game_server(server_data: Dictionary) -> void:
	if server_data.has("id"):
		_save_pref_safe(PREF_SELECTED_SERVER_ID, str(server_data.get("id", "")), PREF_SECTION)
	if server_data.has("api_url"):
		_save_url_pref(PREF_NODE_API_BASE_URL, server_data.get("api_url", ""))
	if server_data.has("ws_url"):
		_save_url_pref(PREF_NODE_WS_URL, server_data.get("ws_url", ""))

static func get_selected_server_id() -> String:
	var saved: Variant = _load_pref_safe(PREF_SELECTED_SERVER_ID, PREF_SECTION)
	if saved == null:
		return ""
	return str(saved)
