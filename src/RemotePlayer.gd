# RemotePlayer - Represents a remote player in the game world
# Synced via WebSocket player_state messages from the backend

extends Node3D
class_name RemotePlayer

@export var peer_id: int = -1
@export var player_name: String = "Remote Player"

var body: Node3D
var label: Label3D
var smooth_position: Vector3 = Vector3.ZERO
var smooth_rotation: Vector3 = Vector3.ZERO
var target_position: Vector3 = Vector3.ZERO
var target_rotation: Vector3 = Vector3.ZERO
var lerp_speed: float = 0.15  # Smoothing speed (0-1, higher = faster)

func _ready() -> void:
	# Create a simple capsule mesh to represent the player
	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	var capsule_mesh: CapsuleMesh = CapsuleMesh.new()
	capsule_mesh.height = 2.0
	capsule_mesh.radius = 0.4
	mesh_instance.mesh = capsule_mesh

	# Add a material
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color.from_hsv(randf() * 360.0 / 360.0, 0.7, 0.8)  # Random color
	mesh_instance.set_surface_override_material(0, material as Material)

	add_child(mesh_instance as Node)
	body = mesh_instance

	# Create name label above player
	label = Label3D.new()
	label.text = player_name
	label.position.y = 1.2
	label.scale = Vector3.ONE * 0.02
	add_child(label)

	smooth_position = global_position
	smooth_rotation = global_rotation
	target_position = global_position
	target_rotation = global_rotation

func _process(delta: float) -> void:
	# Smooth interpolation between current and target position/rotation
	smooth_position = smooth_position.lerp(target_position, lerp_speed)
	smooth_rotation = smooth_rotation.lerp(target_rotation, lerp_speed)

	global_position = smooth_position
	global_rotation = smooth_rotation

func update_state(position: Vector3, rotation: Vector3, velocity: Vector3) -> void:
	"""Update remote player state from server message"""
	target_position = position
	target_rotation = rotation
	# velocity is stored but not actively used for now (could use for prediction)

func set_display_name(new_name: String) -> void:
	"""Update the player's display name"""
	player_name = new_name
	if label:
		label.text = new_name
