class_name EmpireVehicle
extends CharacterBody3D

var game: Node
var driver: EmpirePlayer
var speed := 0.0
var steer := 0.0
var max_speed := 41.0
var reverse_speed := 13.0
var acceleration := 19.0
var braking := 34.0
var camera_pivot: Node3D
var spring_arm: SpringArm3D
var camera: Camera3D
var model: Node3D
var wheel_spinners: Array[Node3D] = []
var front_wheel_mounts: Array[Node3D] = []
var camera_yaw := 0.0
var camera_pitch := -0.18
var camera_look_timer := 0.0
var brand_name := "NOVA C1"
var quality := 1
var body_color := Color("#ff6333")
var paint_material: StandardMaterial3D

func setup(owner_game: Node, color: Color, model_name: String, tier := 1) -> void:
	game = owner_game
	body_color = color
	brand_name = model_name
	quality = tier

func _ready() -> void:
	add_to_group("vehicles")
	collision_layer = 4
	collision_mask = 1
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.05, 1.15, 4.45)
	collider.shape = shape
	collider.position.y = 0.72
	add_child(collider)
	model = Node3D.new()
	add_child(model)
	_build_car()
	camera_pivot = Node3D.new()
	camera_pivot.position = Vector3(0, 1.4, 0)
	add_child(camera_pivot)
	spring_arm = SpringArm3D.new()
	spring_arm.spring_length = 7.2
	spring_arm.position.y = 1.0
	spring_arm.collision_mask = 1
	camera_pivot.add_child(spring_arm)
	camera = Camera3D.new()
	camera.fov = 72.0
	spring_arm.add_child(camera)

func _build_car() -> void:
	var paint := StandardMaterial3D.new()
	paint.albedo_color = body_color
	paint.metallic = 0.72
	paint.roughness = 0.22
	paint_material = paint
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.04, 0.11, 0.17, 0.82)
	glass.metallic = 0.3
	glass.roughness = 0.12
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var trim := StandardMaterial3D.new()
	trim.albedo_color = Color("#10151d")
	trim.metallic = 0.5
	var tire := StandardMaterial3D.new()
	tire.albedo_color = Color("#090b0e")
	tire.roughness = 0.9
	var rim := StandardMaterial3D.new()
	rim.albedo_color = Color("#c5ced8")
	rim.metallic = 0.85
	var lamp := StandardMaterial3D.new()
	lamp.albedo_color = Color("#dff6ff")
	lamp.emission_enabled = true
	lamp.emission = Color("#b8e9ff")
	lamp.emission_energy_multiplier = 2.0
	_part(BoxMesh.new(), Vector3(0, 0.68, 0.05), Vector3(1.96, 0.55, 4.25), paint)
	_part(BoxMesh.new(), Vector3(0, 1.14, 0.14), Vector3(1.68, 0.58, 2.18), glass)
	_part(BoxMesh.new(), Vector3(0, 0.66, -2.13), Vector3(1.72, 0.22, 0.08), trim)
	_part(BoxMesh.new(), Vector3(0, 0.67, 2.13), Vector3(1.64, 0.18, 0.08), trim)
	for side in [-1.0, 1.0]:
		for z_pos in [-1.42, 1.42]:
			var steering_mount := Node3D.new()
			steering_mount.position = Vector3(side * 1.02, 0.47, z_pos)
			model.add_child(steering_mount)
			if z_pos < 0.0:
				front_wheel_mounts.append(steering_mount)
			var axle := Node3D.new()
			axle.rotation.z = PI / 2.0
			steering_mount.add_child(axle)
			var spinner := Node3D.new()
			axle.add_child(spinner)
			var wheel := MeshInstance3D.new()
			var cylinder := CylinderMesh.new()
			cylinder.height = 0.34
			cylinder.top_radius = 0.43
			cylinder.bottom_radius = 0.43
			wheel.mesh = cylinder
			wheel.material_override = tire
			spinner.add_child(wheel)
			var hub := MeshInstance3D.new()
			var hub_cylinder := CylinderMesh.new()
			hub_cylinder.height = 0.36
			hub_cylinder.top_radius = 0.23
			hub_cylinder.bottom_radius = 0.23
			hub.mesh = hub_cylinder
			hub.material_override = rim
			spinner.add_child(hub)
			wheel_spinners.append(spinner)
	for x_pos in [-0.65, 0.65]:
		_part(BoxMesh.new(), Vector3(x_pos, 0.77, -2.17), Vector3(0.42, 0.18, 0.06), lamp)

func set_body_color(color: Color) -> void:
	body_color = color
	if paint_material:
		paint_material.albedo_color = color

func _part(mesh: Mesh, pos: Vector3, size: Vector3, material: Material) -> void:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.position = pos
	part.scale = size
	part.material_override = material
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	model.add_child(part)

func _unhandled_input(event: InputEvent) -> void:
	if driver and event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		camera_yaw -= event.relative.x * 0.0027
		camera_pitch = clampf(camera_pitch - event.relative.y * 0.0023, -0.65, 0.2)
		camera_look_timer = 1.8

func _physics_process(delta: float) -> void:
	if not driver:
		speed = move_toward(speed, 0.0, 5.0 * delta)
		velocity = -global_transform.basis.z * speed
		velocity.y = -2.0
		move_and_slide()
		return
	var throttle: float = Input.get_axis("move_back", "move_forward")
	var steer_input: float = Input.get_axis("move_left", "move_right")
	if throttle > 0.0:
		if speed < -0.5:
			speed = move_toward(speed, 0.0, braking * delta)
		else:
			speed = move_toward(speed, max_speed, acceleration * delta)
	elif throttle < 0.0:
		if speed > 0.5:
			speed = move_toward(speed, 0.0, braking * delta)
		else:
			speed = move_toward(speed, -reverse_speed, acceleration * 0.72 * delta)
	else:
		speed = move_toward(speed, 0.0, 7.5 * delta)
	var speed_ratio: float = clampf(abs(speed) / max_speed, 0.0, 1.0)
	steer = move_toward(steer, steer_input, 3.8 * delta)
	var steering_speed_scale: float = clampf(abs(speed) / 8.0, 0.0, 1.0)
	var steer_strength: float = lerpf(1.55, 0.62, speed_ratio)
	if abs(speed) > 0.25:
		rotation.y -= steer * steer_strength * steering_speed_scale * sign(speed) * delta
	if Input.is_action_pressed("handbrake"):
		speed = move_toward(speed, 0.0, 18.0 * delta)
		if abs(speed) > 5.0:
			rotation.y -= steer * 0.8 * sign(speed) * delta
	var forward := -global_transform.basis.z
	velocity = forward * speed
	velocity.y = -3.0
	move_and_slide()
	model.rotation.z = lerp(model.rotation.z, -steer * speed_ratio * 0.045, 6.0 * delta)
	for mount in front_wheel_mounts:
		mount.rotation.y = lerp_angle(mount.rotation.y, -steer * 0.42, 10.0 * delta)
	for spinner in wheel_spinners:
		spinner.rotation.y -= (speed / 0.43) * delta
	camera_look_timer = maxf(0.0, camera_look_timer - delta)
	if camera_look_timer <= 0.0:
		camera_yaw = lerp_angle(camera_yaw, 0.0, 2.2 * delta)
		camera_pitch = lerpf(camera_pitch, -0.18, 2.2 * delta)
	camera_pivot.rotation = Vector3(camera_pitch, camera_yaw, 0.0)
	if game:
		game.update_vehicle_hud(abs(speed) * 3.6, brand_name)

func enter(player: EmpirePlayer) -> void:
	driver = player
	player.set_active(false)
	camera.current = true
	if game:
		game.set_driving(true, self)

func exit() -> void:
	if not driver:
		return
	var player := driver
	driver = null
	player.global_position = global_position + global_transform.basis.x * 2.2 + Vector3.UP * 0.2
	player.yaw = rotation.y
	player.set_active(true)
	if game:
		game.set_driving(false, null)
