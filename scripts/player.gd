class_name EmpirePlayer
extends CharacterBody3D

var enabled := true
var walk_speed := 7.5
var sprint_speed := 12.0
var gravity := 28.0
var camera_pivot: Node3D
var spring_arm: SpringArm3D
var camera: Camera3D
var body_visual: Node3D
var yaw := 0.0
var pitch := -0.22
var left_leg: Node3D
var right_leg: Node3D
var left_arm: Node3D
var right_arm: Node3D
var walk_phase := 0.0
var remote_proxy := false
var remote_target_position := Vector3.ZERO
var remote_target_yaw := 0.0
var remote_is_moving := false
var remote_company := ""
var remote_color := Color("#1677ff")

func configure_remote(company: String, color: Color) -> void:
	remote_proxy = true
	enabled = false
	remote_company = company
	remote_color = color

func _ready() -> void:
	add_to_group("player")
	collision_layer = 0 if remote_proxy else 2
	collision_mask = 1
	floor_snap_length = 0.35
	floor_max_angle = deg_to_rad(48.0)
	safe_margin = 0.04
	var collider := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.48
	capsule.height = 1.8
	collider.shape = capsule
	collider.position.y = 0.9
	add_child(collider)
	body_visual = Node3D.new()
	body_visual.position.y = 0.9
	add_child(body_visual)
	_build_character()
	camera_pivot = Node3D.new()
	camera_pivot.position.y = 1.45
	add_child(camera_pivot)
	spring_arm = SpringArm3D.new()
	spring_arm.spring_length = 5.8
	spring_arm.collision_mask = 1
	spring_arm.margin = 0.18
	camera_pivot.add_child(spring_arm)
	camera = Camera3D.new()
	camera.fov = 68.0
	spring_arm.add_child(camera)
	if remote_proxy:
		_apply_remote_appearance()
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _apply_remote_appearance() -> void:
	for child in body_visual.get_children():
		if child is MeshInstance3D:
			var material := child.material_override as StandardMaterial3D
			if material and material.albedo_color.is_equal_approx(Color("#175cd3")):
				var remote_material := material.duplicate() as StandardMaterial3D
				remote_material.albedo_color = remote_color
				child.material_override = remote_material
	var nameplate := Label3D.new()
	nameplate.text = remote_company
	nameplate.position = Vector3(0, 2.35, 0)
	nameplate.font_size = 34
	nameplate.outline_size = 7
	nameplate.modulate = remote_color.lightened(0.35)
	nameplate.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	nameplate.no_depth_test = true
	add_child(nameplate)

func apply_remote_state(target_position: Vector3, facing_yaw: float, moving: bool) -> void:
	remote_target_position = target_position
	remote_target_yaw = facing_yaw
	remote_is_moving = moving

func _build_character() -> void:
	var jacket := StandardMaterial3D.new()
	jacket.albedo_color = Color("#175cd3")
	jacket.roughness = 0.72
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color("#152438")
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color("#efb184")
	_mesh_part(CapsuleMesh.new(), Vector3(0, 0.12, 0), Vector3(0.72, 0.82, 0.46), jacket)
	_mesh_part(SphereMesh.new(), Vector3(0, 0.78, 0), Vector3(0.42, 0.46, 0.42), skin)
	left_leg = _limb(Vector3(-0.2, -0.24, 0), Vector3(0.22, 0.8, 0.25), dark)
	right_leg = _limb(Vector3(0.2, -0.24, 0), Vector3(0.22, 0.8, 0.25), dark)
	left_arm = _limb(Vector3(-0.48, 0.34, 0), Vector3(0.18, 0.72, 0.2), jacket)
	right_arm = _limb(Vector3(0.48, 0.34, 0), Vector3(0.18, 0.72, 0.2), jacket)

func _limb(pivot_position: Vector3, size: Vector3, material: Material) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = pivot_position
	body_visual.add_child(pivot)
	var part := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	part.mesh = mesh
	part.position.y = -size.y * 0.5
	part.scale = size
	part.material_override = material
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	pivot.add_child(part)
	return pivot

func _mesh_part(mesh: Mesh, pos: Vector3, scale_value: Vector3, material: Material) -> void:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.position = pos
	part.scale = scale_value
	part.material_override = material
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	body_visual.add_child(part)

func _input(event: InputEvent) -> void:
	if remote_proxy:
		return
	if event is InputEventMouseMotion and enabled and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= event.relative.x * 0.0032
		pitch = clamp(pitch - event.relative.y * 0.0028, -0.95, 0.32)
	if event.is_action_pressed("pause_menu"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED

func _physics_process(delta: float) -> void:
	if remote_proxy:
		global_position = global_position.lerp(remote_target_position, minf(1.0, delta * 12.0))
		body_visual.rotation.y = lerp_angle(body_visual.rotation.y, remote_target_yaw, minf(1.0, delta * 12.0))
		_animate_walk(delta, remote_is_moving, walk_speed)
		return
	if not enabled:
		velocity = Vector3.ZERO
		return
	camera_pivot.rotation = Vector3(pitch, yaw, 0)
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0
		if Input.is_action_just_pressed("jump"):
			velocity.y = 10.0
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var forward := Vector3(-sin(yaw), 0, -cos(yaw))
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	var direction := (right * input.x + forward * -input.y).normalized()
	var target_speed := sprint_speed if Input.is_action_pressed("sprint") else walk_speed
	var target := direction * target_speed
	var grounded := is_on_floor()
	var control := 44.0 if grounded and direction.length_squared() > 0.01 else 54.0
	if not grounded:
		control = 12.0
	velocity.x = move_toward(velocity.x, target.x, control * delta)
	velocity.z = move_toward(velocity.z, target.z, control * delta)
	if direction.length_squared() > 0.01:
		var facing := atan2(-direction.x, -direction.z)
		body_visual.rotation.y = lerp_angle(body_visual.rotation.y, facing, 14.0 * delta)
	move_and_slide()
	_animate_walk(delta, direction.length_squared() > 0.01 and is_on_floor(), target_speed)

func _animate_walk(delta: float, moving: bool, target_speed: float) -> void:
	var target_swing := 0.0
	if moving:
		walk_phase += delta * (9.0 if target_speed == walk_speed else 13.0)
		target_swing = sin(walk_phase) * (0.58 if target_speed == walk_speed else 0.76)
		body_visual.position.y = 0.9 + absf(sin(walk_phase * 2.0)) * 0.035
	else:
		body_visual.position.y = lerpf(body_visual.position.y, 0.9, 12.0 * delta)
	left_leg.rotation.x = lerpf(left_leg.rotation.x, target_swing, 14.0 * delta)
	right_leg.rotation.x = lerpf(right_leg.rotation.x, -target_swing, 14.0 * delta)
	left_arm.rotation.x = lerpf(left_arm.rotation.x, -target_swing * 0.72, 14.0 * delta)
	right_arm.rotation.x = lerpf(right_arm.rotation.x, target_swing * 0.72, 14.0 * delta)

func set_active(value: bool) -> void:
	enabled = value
	visible = value
	set_physics_process(value)
	if value:
		camera.current = true
