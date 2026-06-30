class_name EmpireMinimap
extends Control

const WORLD_EXTENT := 820.0

var game: Node3D

func configure(owner_game: Node3D) -> void:
	game = owner_game
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	queue_redraw()

func _process(_delta: float) -> void:
	if game:
		queue_redraw()

func _world_to_map(world_position: Vector3) -> Vector2:
	var drawable := size - Vector2(18, 18)
	var scale_factor := minf(drawable.x, drawable.y) / (WORLD_EXTENT * 2.0)
	var center := size * 0.5
	var point := center + Vector2(world_position.x, -world_position.z) * scale_factor
	return Vector2(
		clampf(point.x, 9.0, size.x - 9.0),
		clampf(point.y, 9.0, size.y - 9.0)
	)

func _draw() -> void:
	if not game or size.x <= 0.0 or size.y <= 0.0:
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color("#07121c"))
	draw_rect(Rect2(Vector2(5, 5), size - Vector2(10, 10)), Color("#123049"), false, 2.0)

	# Downtown grid and the regional ring roads mirror the playable world.
	for coordinate in [-120.0, -40.0, 40.0, 120.0]:
		var horizontal_start := _world_to_map(Vector3(-230, 0, coordinate))
		var horizontal_end := _world_to_map(Vector3(230, 0, coordinate))
		draw_line(horizontal_start, horizontal_end, Color("#405362"), 2.0)
		var vertical_start := _world_to_map(Vector3(coordinate, 0, -230))
		var vertical_end := _world_to_map(Vector3(coordinate, 0, 230))
		draw_line(vertical_start, vertical_end, Color("#405362"), 2.0)
	for coordinate in [-650.0, 650.0]:
		draw_line(
			_world_to_map(Vector3(-680, 0, coordinate)),
			_world_to_map(Vector3(680, 0, coordinate)),
			Color("#526877"),
			2.0
		)
		draw_line(
			_world_to_map(Vector3(coordinate, 0, -680)),
			_world_to_map(Vector3(coordinate, 0, 680)),
			Color("#526877"),
			2.0
		)
	draw_line(_world_to_map(Vector3(-680, 0, 40)), _world_to_map(Vector3(680, 0, 40)), Color("#526877"), 2.0)
	draw_line(_world_to_map(Vector3(40, 0, -800)), _world_to_map(Vector3(40, 0, 680)), Color("#526877"), 2.0)

	var terminals: Array = game.get("interactables")
	for terminal in terminals:
		if not is_instance_valid(terminal):
			continue
		var marker_color := _location_color(str(terminal.get_meta("kind", "")))
		draw_circle(_world_to_map(terminal.global_position), 3.5, marker_color)

	var remote_players: Dictionary = game.get("remote_players")
	var online_peers: Dictionary = game.get("online_peers")
	for peer_id in remote_players:
		var remote = remote_players[peer_id]
		if not is_instance_valid(remote):
			continue
		var identity: Dictionary = online_peers.get(peer_id, {"color": "1677ff"})
		var remote_color := Color(str(identity.get("color", "1677ff")))
		draw_circle(_world_to_map(remote.global_position), 4.5, remote_color)
		draw_circle(_world_to_map(remote.global_position), 6.5, Color.WHITE, false, 1.0)

	var local_player = game.get("player")
	var current_vehicle = game.get("current_vehicle")
	if not is_instance_valid(local_player):
		return
	var local_position: Vector3 = current_vehicle.global_position if is_instance_valid(current_vehicle) else local_player.global_position
	var local_yaw: float = current_vehicle.rotation.y if is_instance_valid(current_vehicle) else local_player.body_visual.rotation.y
	var arrow_center := _world_to_map(local_position)
	var forward := Vector2(0, -10).rotated(-local_yaw)
	var right := Vector2(5.5, 5.5).rotated(-local_yaw)
	var left := Vector2(-5.5, 5.5).rotated(-local_yaw)
	var brand_color: Color = game.get("brand_color")
	draw_colored_polygon(PackedVector2Array([
		arrow_center + forward,
		arrow_center + right,
		arrow_center + left,
	]), brand_color.lightened(0.2))
	draw_polyline(PackedVector2Array([
		arrow_center + forward,
		arrow_center + right,
		arrow_center + left,
		arrow_center + forward,
	]), Color.WHITE, 1.5)

	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(size.x - 19, 18), "N", HORIZONTAL_ALIGNMENT_CENTER, 14, 13, Color("#8fe7ff"))

func _location_color(kind: String) -> Color:
	match kind:
		"factory", "storage", "design":
			return Color("#ff9a45")
		"dealership", "auction":
			return Color("#45e0ac")
		"engine_shop", "chassis_shop", "electronics_shop", "dock_imports":
			return Color("#63b8ff")
		"race":
			return Color("#f5ce3d")
		_:
			return Color("#b889ff")
