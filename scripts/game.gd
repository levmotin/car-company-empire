extends Node3D

const PlayerScript = preload("res://scripts/player.gd")
const VehicleScript = preload("res://scripts/vehicle.gd")
const ONLINE_SERVER_URL := "wss://car-company-empire-online.onrender.com/multiplayer"
const ACCOUNT_API_BASE_URL := "https://car-company-empire-online.onrender.com/api"
const NETWORK_SEND_INTERVAL := 0.05
const AUTOSAVE_INTERVAL := 10.0

var player: EmpirePlayer
var current_vehicle: EmpireVehicle
var money := 25000
var reputation := 0
var company_level := 1
var research := 0
var player_username := "DRIVER"
var company_name := "NOVA MOTORS"
var brand_color := Color("#ff6333")
var inventory := {"Chassis": 1, "Engine": 1, "Transmission": 1, "Wheels": 1, "Electronics": 0}
var manufactured := 0
var manufactured_vehicles: Array[EmpireVehicle] = []
var total_built := 0
var total_sales := 0
var objective_stage := 0
var starter_vehicle: EmpireVehicle
var interactables: Array[Node3D] = []
var ui: CanvasLayer
var hud: Control
var action_label: Label
var objective_label: Label
var money_label: Label
var rep_label: Label
var speed_panel: PanelContainer
var speed_label: Label
var toast: Label
var modal: PanelContainer
var modal_body: VBoxContainer
var company_setup: Control
var loading_screen: Control
var loading_label: Label
var toast_tween: Tween
var time_of_day := 9.2
var sun: DirectionalLight3D
var environment: WorldEnvironment
var nearest: Node3D
var panel_open := false
var style_panel: StyleBoxFlat
var style_button: StyleBoxFlat
var city_model_cache := {}
var factory_plots: Array[Node3D] = []
var factory_slot_centers: Array[Vector3] = []
var factory_slot_terminals := {}
var factory_peer_slots := {}
var local_factory_slot := -1
var online_mode := "menu"
var online_status_label: Label
var online_roster_panel: PanelContainer
var online_roster_label: Label
var online_peers := {}
var remote_players := {}
var remote_vehicles := {}
var network_send_accumulator := 0.0
var online_socket: WebSocketPeer
var online_peer_id := 0
var online_connected := false
var auth_token := ""
var auth_request: HTTPRequest
var save_request: HTTPRequest
var delete_request: HTTPRequest
var save_in_flight := false
var progress_dirty := false
var autosave_accumulator := 0.0
var game_started := false

func _ready() -> void:
	_setup_styles()
	_setup_environment()
	_build_world()
	_spawn_player()
	_spawn_starter_car()
	_build_ui()
	player.set_active(false)
	hud.visible = false
	auth_request = HTTPRequest.new()
	auth_request.request_completed.connect(_on_auth_request_completed)
	add_child(auth_request)
	save_request = HTTPRequest.new()
	save_request.request_completed.connect(_on_save_request_completed)
	add_child(save_request)
	delete_request = HTTPRequest.new()
	delete_request.request_completed.connect(_on_delete_request_completed)
	add_child(delete_request)
	_show_auth_screen(true)

func _setup_styles() -> void:
	style_panel = StyleBoxFlat.new()
	style_panel.bg_color = Color(0.025, 0.055, 0.09, 0.94)
	style_panel.border_color = Color(0.12, 0.3, 0.48, 0.9)
	style_panel.set_border_width_all(1)
	style_panel.set_corner_radius_all(12)
	style_panel.content_margin_left = 18
	style_panel.content_margin_right = 18
	style_panel.content_margin_top = 14
	style_panel.content_margin_bottom = 14
	style_button = StyleBoxFlat.new()
	style_button.bg_color = Color("#1768d5")
	style_button.set_corner_radius_all(7)
	style_button.content_margin_left = 16
	style_button.content_margin_right = 16
	style_button.content_margin_top = 9
	style_button.content_margin_bottom = 9

func _setup_environment() -> void:
	environment = WorldEnvironment.new()
	var env := Environment.new()
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("#168fd1")
	sky_material.sky_horizon_color = Color("#bfe8f5")
	sky_material.ground_horizon_color = Color("#c8e3df")
	sky_material.ground_bottom_color = Color("#688878")
	sky_material.sun_angle_max = 18.0
	sky_material.sun_curve = 0.08
	sky.sky_material = sky_material
	env.sky = sky
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#cfe9ff")
	env.ambient_light_energy = 0.65
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	# Keep the city crisp and readable. Height fog previously saturated the
	# entire playable area because the map sits below the configured fog layer.
	env.fog_enabled = false
	environment.environment = env
	add_child(environment)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -32, 0)
	sun.light_color = Color("#fff1cf")
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 180.0
	add_child(sun)

func _build_world() -> void:
	_build_clean_map()

func _build_clean_map() -> void:
	# One continuous collider under the entire town. Everything at street level
	# is visual geometry, so there are no hidden curbs or stacked road colliders.
	_box("Terrain", Vector3(180, -0.55, 0), Vector3(1140, 1, 900), Color("#69a45d"), true)
	_build_clean_road_grid()
	_build_clean_downtown()
	_build_clean_dealership()
	_build_clean_suppliers()
	_build_clean_residential()
	_build_online_factory_park()
	_build_clean_airport()
	_build_clean_harbor()
	_build_reclaimed_neighborhood()
	_build_clean_landmarks()
	_build_clean_street_props()
	_build_clean_power_plant()
	_build_clean_border()

func _build_reclaimed_neighborhood() -> void:
	var center := Vector3(-180, 0, -180)
	_clean_lot(center, Vector3(92, 0, 92), Color("#75ad64"))
	var homes := [
		[Vector3(-205, 0, -205), "building-a", 0.0],
		[Vector3(-158, 0, -205), "building-c", 0.0],
		[Vector3(-205, 0, -158), "building-h", PI],
		[Vector3(-158, 0, -158), "building-b", PI],
	]
	for home in homes:
		_spawn_city_model("res://assets/city/kenney/" + str(home[1]) + ".glb", home[0], 15.0, home[2], Vector3(15, 21, 15))
		_box("GardenHedge", home[0] + Vector3(0, 0.55, -11), Vector3(17, 1.1, 0.7), Color("#2b8248"), false)

func _build_giant_expansion() -> void:
	_build_outer_highways()
	_build_grand_prix_district()
	_build_auction_district()
	_build_logistics_park()
	_build_country_town()
	_build_mountain_resort()
	_build_dense_neighborhoods()

func _build_dense_neighborhoods() -> void:
	var models := [
		"low-detail-building-a", "low-detail-building-b", "low-detail-building-c",
		"low-detail-building-d", "low-detail-building-e", "low-detail-building-f",
		"low-detail-building-g", "low-detail-building-h", "low-detail-building-i",
		"low-detail-building-j", "low-detail-building-k", "low-detail-building-l",
		"low-detail-building-m", "low-detail-building-n",
	]
	var placed := 0
	var spacing := 58
	var row_index := 0
	for z in range(-820, 821, spacing):
		var column_index := 0
		for x in range(-820, 821, spacing):
			var stagger := 10.0 if row_index % 2 == 1 else 0.0
			var pos := Vector3(float(x) + stagger, 0, float(z))
			if _can_place_neighborhood_building(pos):
				var model_index: int = absi(column_index * 5 + row_index * 3) % models.size()
				var model_path: String = "res://assets/city/kenney/" + str(models[model_index]) + ".glb"
				var model_scale: float = 18.0 + float(absi(column_index * 7 + row_index * 11) % 5)
				var facing := PI if row_index % 2 == 0 else 0.0
				_box("ResidentialLot", Vector3(pos.x, -0.006, pos.z), Vector3(31, 0.018, 31), Color("#72aa62"), false)
				_spawn_city_model(model_path, pos, model_scale, facing, Vector3(17, 23, 17))
				if placed % 2 == 0:
					_box("NeighborhoodHedge", pos + Vector3(0, 0.55, -17), Vector3(24, 1.1, 0.7), Color("#2b8248"), false)
				if placed % 5 == 0:
					_tree(pos + Vector3(18, 0, 15))
				placed += 1
			column_index += 1
		row_index += 1

func _can_place_neighborhood_building(pos: Vector3) -> bool:
	# Central city and authored destination parcels.
	if absf(pos.x) < 300.0 and absf(pos.z) < 330.0:
		return false
	if _inside_expansion_area(pos, Vector3(-500, 0, -420), Vector2(165, 135)):
		return false
	if _inside_expansion_area(pos, Vector3(500, 0, -420), Vector2(140, 120)):
		return false
	if _inside_expansion_area(pos, Vector3(500, 0, 450), Vector2(150, 125)):
		return false
	if _inside_expansion_area(pos, Vector3(-500, 0, 450), Vector2(150, 125)):
		return false
	if _inside_expansion_area(pos, Vector3(40, 0, -740), Vector2(160, 95)):
		return false
	# Clear every arterial and the orbital highway.
	for road_x in [40.0, -650.0, 650.0]:
		if absf(pos.x - road_x) < 30.0:
			return false
	for road_z in [40.0, -650.0, 650.0, -420.0, 450.0]:
		if absf(pos.z - road_z) < 30.0:
			return false
	return true

func _inside_expansion_area(pos: Vector3, center: Vector3, half_size: Vector2) -> bool:
	return absf(pos.x - center.x) < half_size.x and absf(pos.z - center.z) < half_size.y

func _build_outer_highways() -> void:
	# Existing streets at x/z 40 continue into a broad regional road network.
	_expansion_road(Vector3(-465, 0, 40), Vector3(470, 0, 24), true)
	_expansion_road(Vector3(465, 0, 40), Vector3(470, 0, 24), true)
	_expansion_road(Vector3(40, 0, -465), Vector3(24, 0, 470), false)
	_expansion_road(Vector3(40, 0, 465), Vector3(24, 0, 470), false)
	# Large square orbital highway, roughly three times the central city's span.
	_expansion_road(Vector3(0, 0, -650), Vector3(1324, 0, 24), true)
	_expansion_road(Vector3(0, 0, 650), Vector3(1324, 0, 24), true)
	_expansion_road(Vector3(-650, 0, 0), Vector3(24, 0, 1324), false)
	_expansion_road(Vector3(650, 0, 0), Vector3(24, 0, 1324), false)
	# District branches.
	_expansion_road(Vector3(-305, 0, -420), Vector3(690, 0, 18), true)
	_expansion_road(Vector3(345, 0, -420), Vector3(610, 0, 18), true)
	_expansion_road(Vector3(-305, 0, 450), Vector3(690, 0, 18), true)
	_expansion_road(Vector3(345, 0, 450), Vector3(610, 0, 18), true)
	for data in [
		[Vector3(-315, 0, -620), "WEST LOOP  •  GRAND PRIX"],
		[Vector3(355, 0, -620), "EAST LOOP  •  AUCTION"],
		[Vector3(-315, 0, 620), "COUNTRY TOWN"],
		[Vector3(355, 0, 620), "LOGISTICS PARK"],
	]:
		_highway_sign(data[0], data[1])

func _expansion_road(pos: Vector3, size: Vector3, horizontal: bool) -> void:
	var visual_size := Vector3(size.x, 0.025, size.z)
	_clean_asphalt(Vector3(pos.x, -0.032, pos.z), visual_size)
	if horizontal:
		for side in [-1.0, 1.0]:
			_box("HighwayEdge", Vector3(pos.x, -0.01, pos.z + side * size.z * 0.42), Vector3(size.x, 0.012, 0.22), Color("#f2f1ea"), false)
		for x in range(int(pos.x - size.x * 0.48), int(pos.x + size.x * 0.48), 18):
			_box("HighwayMark", Vector3(x, -0.008, pos.z), Vector3(8, 0.014, 0.3), Color("#f1c83c"), false)
	else:
		for side in [-1.0, 1.0]:
			_box("HighwayEdge", Vector3(pos.x + side * size.x * 0.42, -0.01, pos.z), Vector3(0.22, 0.012, size.z), Color("#f2f1ea"), false)
		for z in range(int(pos.z - size.z * 0.48), int(pos.z + size.z * 0.48), 18):
			_box("HighwayMark", Vector3(pos.x, -0.008, z), Vector3(0.3, 0.014, 8), Color("#f1c83c"), false)

func _highway_sign(pos: Vector3, text: String) -> void:
	_box("SignPost", pos + Vector3(-5, 3.5, 0), Vector3(0.4, 7, 0.4), Color("#384850"), false)
	_box("SignPost", pos + Vector3(5, 3.5, 0), Vector3(0.4, 7, 0.4), Color("#384850"), false)
	_box("HighwaySign", pos + Vector3(0, 6.5, 0), Vector3(14, 4.5, 0.5), Color("#176348"), false)
	_sign(pos + Vector3(0, 6.5, -0.4), text, Color.WHITE)

func _build_grand_prix_district() -> void:
	var center := Vector3(-500, 0, -420)
	_clean_lot(center, Vector3(280, 0, 220), Color("#4e9854"))
	var points: Array[Vector3] = []
	for i in range(64):
		var angle := TAU * float(i) / 64.0
		var radius_x := 118.0 + sin(angle * 3.0) * 10.0
		var radius_z := 78.0 + cos(angle * 2.0) * 7.0
		points.append(center + Vector3(cos(angle) * radius_x, 0, sin(angle) * radius_z))
	for i in range(points.size()):
		_track_piece(points[i], points[(i + 1) % points.size()], 16.0)
	# Pits, grandstand and paddock.
	_spawn_city_model("res://assets/city/kenney/building-k.glb", Vector3(-500, 0, -420), 18.0, PI * 0.5, Vector3(38, 27, 17))
	_box("GrandstandBase", Vector3(-500, 3.5, -320), Vector3(110, 7, 18), Color("#69757c"), true)
	for row in range(5):
		_box("GrandstandSeat", Vector3(-500, 5.0 + row * 1.1, -326 + row * 2.0), Vector3(104, 0.7, 2.0), [Color("#2f78bf"), Color("#e7c83e"), Color("#e2554a")][row % 3], false)
	_terminal(Vector3(-500, 1.1, -347), "race", "GRAND PRIX CIRCUIT", Color("#f5ce3d"))
	_sign(Vector3(-500, 12, -315), "EMPIRE MOTORSPORT PARK", Color("#ffe26c"))

func _track_piece(a: Vector3, b: Vector3, width: float) -> void:
	var midpoint := (a + b) * 0.5
	var delta := b - a
	var piece := _box("RaceTrack", Vector3(midpoint.x, -0.02, midpoint.z), Vector3(width, 0.035, delta.length() + 1.0), Color("#2d3439"), false)
	piece.rotation.y = atan2(delta.x, delta.z)
	var line := _box("TrackLine", Vector3(midpoint.x, 0.005, midpoint.z), Vector3(0.28, 0.012, delta.length() + 0.7), Color("#f3f2ea"), false)
	line.rotation.y = atan2(delta.x, delta.z)

func _build_auction_district() -> void:
	var center := Vector3(500, 0, -420)
	_clean_lot(center, Vector3(230, 0, 190), Color("#7e878a"))
	_spawn_city_model("res://assets/city/kenney/building-j.glb", center + Vector3(0, 0, -45), 32.0, 0.0, Vector3(67, 55, 43))
	_spawn_city_model("res://assets/city/kenney/building-e.glb", center + Vector3(-72, 0, 25), 24.0, PI * 0.5, Vector3(39, 22, 24))
	for x in range(420, 581, 20):
		_box("AuctionParkingLine", Vector3(x, 0.02, -350), Vector3(0.16, 0.014, 28), Color("#f1f1eb"), false)
	_terminal(center + Vector3(0, 1.1, 35), "auction", "VEHICLE AUCTION", Color("#d99bff"))
	_sign(center + Vector3(0, 18, -68), "EMPIRE MOTOR AUCTION", Color("#e4b5ff"))

func _build_logistics_park() -> void:
	var center := Vector3(500, 0, 450)
	_clean_lot(center, Vector3(250, 0, 190), Color("#747c7f"))
	for offset in [-72.0, 0.0, 72.0]:
		_spawn_city_model("res://assets/city/kenney/building-k.glb", center + Vector3(offset, 0, 15), 28.0, 0.0, Vector3(58, 41, 27))
	for i in range(24):
		var x := 405.0 + float(i % 8) * 24.0
		var z := 385.0 + float(i / 8) * 8.0
		_box("FreightContainer", Vector3(x, 1.6, z), Vector3(20, 3.1, 6), [Color("#cc4e43"), Color("#316fb0"), Color("#d1a537")][i % 3], false)
	_terminal(center + Vector3(0, 1.1, -55), "dock_imports", "FREIGHT MARKET", Color("#f0b849"))
	_sign(center + Vector3(0, 13, 65), "CONTINENTAL LOGISTICS", Color("#86d9ff"))

func _build_country_town() -> void:
	var center := Vector3(-500, 0, 450)
	_clean_lot(center, Vector3(260, 0, 200), Color("#75ad64"))
	var town_positions := [
		Vector3(-585, 0, 405), Vector3(-535, 0, 405), Vector3(-475, 0, 405), Vector3(-420, 0, 405),
		Vector3(-585, 0, 490), Vector3(-530, 0, 490), Vector3(-470, 0, 490), Vector3(-415, 0, 490),
	]
	var town_models := ["building-a", "building-c", "building-d", "building-h", "building-b", "building-e", "building-f", "building-i"]
	for index in range(town_positions.size()):
		_spawn_city_model("res://assets/city/kenney/" + town_models[index] + ".glb", town_positions[index], 18.0, PI if index < 4 else 0.0, Vector3(18, 25, 18))
	for x in range(-600, -399, 35):
		_tree(Vector3(x, 0, 450))
	_sign(center + Vector3(0, 10, -86), "GREENFIELD", Color("#fff0a8"))

func _build_mountain_resort() -> void:
	var center := Vector3(40, 0, -740)
	_clean_lot(center, Vector3(260, 0, 120), Color("#669b5d"))
	for x in [-70.0, -20.0, 35.0, 90.0, 145.0]:
		_spawn_city_model("res://assets/city/kenney/building-h.glb", Vector3(x, 0, -735), 16.0, PI, Vector3(15, 22, 17))
	for x in range(-90, 171, 35):
		_tree(Vector3(x, 0, -690))
	_sign(center + Vector3(0, 12, -50), "NORTH RIDGE RESORT", Color("#e8f4ff"))

func _build_clean_road_grid() -> void:
	var road_centers := [-120.0, -40.0, 40.0, 120.0]
	var map_edge := 230.0
	var road_width := 16.0
	# Horizontal roads are continuous.
	for z in road_centers:
		_clean_asphalt(Vector3(0, -0.032, z), Vector3(map_edge * 2.0, 0.025, road_width))
		for x in range(-220, 221, 18):
			if _away_from_intersections(float(x), road_centers, 13.0):
				_box("LaneMark", Vector3(x, -0.012, z), Vector3(7.0, 0.012, 0.24), Color("#f0ca45"), false)
	# Vertical roads stop at each horizontal road, so no surfaces are stacked.
	var z_edges := [-230.0, -128.0, -112.0, -48.0, -32.0, 32.0, 48.0, 112.0, 128.0, 230.0]
	for x in road_centers:
		for index in range(0, z_edges.size(), 2):
			var start_z: float = z_edges[index]
			var end_z: float = z_edges[index + 1]
			var length := end_z - start_z
			_clean_asphalt(Vector3(x, -0.031, (start_z + end_z) * 0.5), Vector3(road_width, 0.025, length))
			for z in range(int(start_z + 8.0), int(end_z - 7.0), 18):
				_box("LaneMark", Vector3(x, -0.011, z), Vector3(0.24, 0.012, 7.0), Color("#f0ca45"), false)
	# Every city block gets one clean sidewalk slab, inset from the roads.
	var block_ranges := [
		Vector2(-230, -128), Vector2(-112, -48), Vector2(-32, 32),
		Vector2(48, 112), Vector2(128, 230),
	]
	for x_range in block_ranges:
		for z_range in block_ranges:
			var min_x: float = x_range.x
			var max_x: float = x_range.y
			var min_z: float = z_range.x
			var max_z: float = z_range.y
			var center := Vector3((min_x + max_x) * 0.5, -0.025, (min_z + max_z) * 0.5)
			_box("SidewalkBlock", center, Vector3(max_x - min_x - 4.0, 0.04, max_z - min_z - 4.0), Color("#c7c7c1"), false)
	# Simple, consistently placed street lamps. They sit on block corners only.
	for x in [-132.0, -28.0, 28.0, 132.0]:
		for z in [-132.0, -28.0, 28.0, 132.0]:
			_clean_street_lamp(Vector3(x, 0, z))
	_build_clean_intersections(road_centers, block_ranges)

func _build_clean_intersections(road_centers: Array, block_ranges: Array) -> void:
	# Continuous white edge lines stop before junctions, avoiding overlapping paint.
	for z in road_centers:
		for road_range in block_ranges:
			var length: float = road_range.y - road_range.x
			var center_x: float = (road_range.x + road_range.y) * 0.5
			for side in [-1.0, 1.0]:
				_box("RoadEdge", Vector3(center_x, -0.01, z + side * 6.4), Vector3(length, 0.012, 0.18), Color("#f5f4ee"), false)
	for x in road_centers:
		for road_range in block_ranges:
			var length: float = road_range.y - road_range.x
			var center_z: float = (road_range.x + road_range.y) * 0.5
			for side in [-1.0, 1.0]:
				_box("RoadEdge", Vector3(x + side * 6.4, -0.009, center_z), Vector3(0.18, 0.012, length), Color("#f5f4ee"), false)
	# Two zebra crossings and four stop bars per junction.
	for x in road_centers:
		for z in road_centers:
			for stripe in range(-5, 6):
				_box("Crosswalk", Vector3(x + stripe * 1.15, -0.006, z - 10.0), Vector3(0.7, 0.014, 3.2), Color("#f5f4ef"), false)
				_box("Crosswalk", Vector3(x - 10.0, -0.005, z + stripe * 1.15), Vector3(3.2, 0.014, 0.7), Color("#f5f4ef"), false)
			_box("StopBar", Vector3(x, -0.005, z + 8.5), Vector3(14, 0.015, 0.35), Color("#f5f4ef"), false)
			_box("StopBar", Vector3(x + 8.5, -0.004, z), Vector3(0.35, 0.015, 14), Color("#f5f4ef"), false)
			_clean_traffic_signal(Vector3(x + 10.5, 0, z + 10.5))

func _clean_traffic_signal(pos: Vector3) -> void:
	var metal := Color("#2b3740")
	_box("SignalPole", pos + Vector3(0, 2.8, 0), Vector3(0.18, 5.6, 0.18), metal, false)
	_box("SignalArm", pos + Vector3(-2.7, 5.25, 0), Vector3(5.4, 0.18, 0.18), metal, false)
	var housing := _box("SignalHead", pos + Vector3(-5.1, 4.8, 0), Vector3(0.8, 1.8, 0.7), Color("#131b20"), false)
	for index in range(3):
		var lamp := MeshInstance3D.new()
		var lamp_mesh := SphereMesh.new()
		lamp_mesh.radius = 0.18
		lamp_mesh.height = 0.36
		lamp_mesh.radial_segments = 8
		lamp_mesh.rings = 4
		lamp.mesh = lamp_mesh
		lamp.position = Vector3(0, 0.52 - index * 0.52, -0.38)
		var lamp_material := StandardMaterial3D.new()
		lamp_material.albedo_color = [Color("#e94f45"), Color("#e1b83a"), Color("#44ca71")][index]
		lamp_material.emission_enabled = true
		lamp_material.emission = lamp_material.albedo_color
		lamp_material.emission_energy_multiplier = 1.5 if index == 2 else 0.2
		lamp.material_override = lamp_material
		housing.add_child(lamp)

func _away_from_intersections(value: float, centers: Array, clearance: float) -> bool:
	for center in centers:
		if absf(value - float(center)) < clearance:
			return false
	return true

func _clean_asphalt(pos: Vector3, size: Vector3) -> void:
	_box("Street", pos, size, Color("#353b40"), false)

func _clean_lot(center: Vector3, size: Vector3, color: Color) -> void:
	_box("Lot", Vector3(center.x, -0.001, center.z), Vector3(size.x, 0.018, size.z), color, false)

func _spawn_city_model(
	path: String,
	pos: Vector3,
	uniform_scale: float,
	yaw_value: float,
	collision_size: Vector3 = Vector3.ZERO,
	collision_offset: Vector3 = Vector3.ZERO
) -> Node3D:
	var scene: PackedScene
	if city_model_cache.has(path):
		scene = city_model_cache[path] as PackedScene
	else:
		scene = load(path) as PackedScene
		city_model_cache[path] = scene
	var root := Node3D.new()
	root.name = path.get_file().get_basename()
	root.position = pos
	root.rotation.y = yaw_value
	root.scale = Vector3.ONE * uniform_scale
	if scene:
		var visual := scene.instantiate()
		root.add_child(visual)
	add_child(root)
	if collision_size != Vector3.ZERO:
		_add_model_collision(pos + collision_offset, collision_size, yaw_value)
	return root

func _spawn_city_model_scaled(
	path: String,
	pos: Vector3,
	scale_value: Vector3,
	yaw_value: float,
	collision_size: Vector3
) -> Node3D:
	var scene: PackedScene
	if city_model_cache.has(path):
		scene = city_model_cache[path] as PackedScene
	else:
		scene = load(path) as PackedScene
		city_model_cache[path] = scene
	var root := Node3D.new()
	root.name = path.get_file().get_basename()
	root.position = pos
	root.rotation.y = yaw_value
	root.scale = scale_value
	if scene:
		root.add_child(scene.instantiate())
	add_child(root)
	_add_model_collision(pos, collision_size, yaw_value)
	return root

func _add_model_collision(pos: Vector3, size: Vector3, yaw_value: float) -> void:
	var body := StaticBody3D.new()
	body.name = "ImportedBuildingCollision"
	body.position = pos + Vector3(0, size.y * 0.5, 0)
	body.rotation.y = yaw_value
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	body.add_child(collider)

func _clean_street_lamp(pos: Vector3) -> void:
	_box("LampPost", pos + Vector3(0, 2.8, 0), Vector3(0.16, 5.6, 0.16), Color("#26333c"), false)
	_box("LampHead", pos + Vector3(0, 5.55, 0), Vector3(0.7, 0.18, 0.7), Color("#313e47"), false)
	var light := OmniLight3D.new()
	light.position = pos + Vector3(0, 5.3, 0)
	light.light_color = Color("#ffe2aa")
	light.light_energy = 1.3
	light.omni_range = 12.0
	add_child(light)

func _build_clean_downtown() -> void:
	# One authored asset family is used across the entire active skyline.
	_spawn_city_model("res://assets/city/kenney/building-j.glb", Vector3(-89, 0, -67), 15.0, 0.0, Vector3(31, 26, 20))
	_spawn_city_model("res://assets/city/kenney/building-n.glb", Vector3(-84, 0, 14), 10.0, PI, Vector3(23, 25, 18))
	_spawn_city_model("res://assets/city/kenney/building-k.glb", Vector3(16, 0, -67), 13.0, 0.0, Vector3(27, 19, 13))
	_spawn_city_model("res://assets/city/kenney/building-skyscraper-d.glb", Vector3(-60, 0, -91), 10.0, 0.0, Vector3(13, 55, 14))
	_spawn_city_model("res://assets/city/kenney/building-skyscraper-b.glb", Vector3(-7, 0, -91), 9.0, PI * 0.5, Vector3(13, 40, 13))
	_spawn_city_model("res://assets/city/kenney/building-skyscraper-e.glb", Vector3(-63, 0, 7), 9.0, PI, Vector3(12, 37, 12))
	_spawn_city_model("res://assets/city/kenney/building-skyscraper-a.glb", Vector3(-10, 0, 10), 11.0, PI * 0.5, Vector3(15, 32, 15))
	_spawn_city_model("res://assets/city/kenney/building-n.glb", Vector3(13, 0, 12), 9.0, PI, Vector3(20, 23, 16))
	_sign(Vector3(-80, 8, -49), "DOWNTOWN", Color("#6edcff"))

func _build_online_factory_park() -> void:
	# Sixteen distinct plots match the server's player limit. The road grid keeps
	# every company accessible without placing players on top of one another.
	_clean_asphalt(Vector3(480, -0.03, 0), Vector3(440, 0.025, 18))
	for road_z in [-240.0, -120.0, 0.0, 120.0, 240.0]:
		_clean_asphalt(Vector3(490, -0.025, road_z), Vector3(430, 0.025, 14))
	for road_x in [290.0, 390.0, 490.0, 590.0, 690.0]:
		_clean_asphalt(Vector3(road_x, -0.024, 0), Vector3(14, 0.025, 500))
	_sign(Vector3(490, 11, -270), "ONLINE COMPANY DISTRICT", Color("#73ddff"))
	for row in range(4):
		for column in range(4):
			var slot := row * 4 + column
			var center := Vector3(340.0 + column * 100.0, 0, -180.0 + row * 120.0)
			factory_slot_centers.append(center)
			_build_factory_slot(center, slot)

func _build_factory_slot(center: Vector3, slot: int) -> void:
	_register_factory_plot(center, 0, "AVAILABLE FACTORY", false)
	var plot: Node3D = factory_plots.back()
	plot.name = "FactoryPlot_%02d" % (slot + 1)
	plot.set_meta("factory_slot", slot)
	_clean_lot(center, Vector3(82, 0, 96), Color("#858d90"))
	_building(center + Vector3(0, 6.0, 10), Vector3(72, 12, 48), Color("#d3d8da"))
	var sign_label := _sign(center + Vector3(0, 11.2, -16), "AVAILABLE FACTORY", Color("#6cb9ff"))
	plot.set_meta("sign_label", sign_label)
	_sign(center + Vector3(0, 5.8, 38), "FACTORY %02d" % (slot + 1), Color("#8bc8ff"))
	var terminals: Array[Node3D] = []
	for terminal_data in [
		["factory", "ASSEMBLY LINE", -24.0, Color("#ff8a38")],
		["storage", "PARTS STORAGE", 0.0, Color("#39c7ff")],
		["design", "DESIGN STUDIO", 24.0, Color("#b87cff")],
	]:
		var role := str(terminal_data[0])
		var terminal := _terminal(
			center + Vector3(float(terminal_data[2]), 1.1, -38),
			"rival_factory",
			"UNASSIGNED FACTORY",
			terminal_data[3]
		)
		terminal.set_meta("factory_slot", slot)
		terminal.set_meta("factory_role", role)
		terminal.set_meta("factory_title", str(terminal_data[1]))
		terminals.append(terminal)
	factory_slot_terminals[slot] = terminals

func _build_clean_factory() -> void:
	var center := Vector3(80, 0, 80)
	_register_factory_plot(center, 1, company_name, true)
	_clean_lot(center, Vector3(60, 0, 60), Color("#8b9293"))
	_building(Vector3(82, 6.5, 88), Vector3(56, 13, 42), Color("#d3d8da"))
	_sign(Vector3(82, 12.0, 64.5), "YOUR FACTORY", Color("#ff9a45"))
	_terminal(Vector3(57, 1.1, 58), "factory", "ASSEMBLY LINE", Color("#ff8a38"))
	_terminal(Vector3(80, 1.1, 58), "storage", "PARTS STORAGE", Color("#39c7ff"))
	_terminal(Vector3(103, 1.1, 58), "design", "DESIGN STUDIO", Color("#b87cff"))
	var container_colors := [Color("#d49b24"), Color("#255fba"), Color("#c9463b")]
	for i in range(3):
		_box("FactoryContainer", Vector3(53, 1.45, 76 + i * 8.0), Vector3(5.5, 2.8, 7.0), container_colors[i], false)
	_sign(Vector3(80, 7.5, 110), "INDUSTRIAL", Color("#ffb15c"))

func _build_rival_factory() -> void:
	var center := Vector3(-80, 0, 80)
	_register_factory_plot(center, 2, "RIVAL MOTORS", false)
	_clean_lot(center, Vector3(60, 0, 60), Color("#858c90"))
	_building(Vector3(-80, 6.5, 88), Vector3(56, 13, 42), Color("#d3d8da"))
	_sign(Vector3(-80, 12.0, 64.5), "RIVAL MOTORS", Color("#6cb9ff"))
	_sign(Vector3(-80, 7.5, 110), "PLAYER 2 FACTORY", Color("#8bc8ff"))
	# The interaction marker is informational until a remote peer owns this plot.
	_terminal(Vector3(-80, 1.1, 58), "rival_factory", "VISIT RIVAL FACTORY", Color("#5ea9ee"))

func _register_factory_plot(center: Vector3, owner_peer_id: int, owner_name: String, is_local: bool) -> void:
	var plot := Node3D.new()
	plot.name = "FactoryPlot_" + str(owner_peer_id)
	plot.position = center
	plot.set_meta("owner_peer_id", owner_peer_id)
	plot.set_meta("owner_company", owner_name)
	plot.set_meta("is_local_owner", is_local)
	plot.add_to_group("factory_plots")
	add_child(plot)
	factory_plots.append(plot)

func _assign_factory_owner(peer_id: int, slot: int, owner_company: String, is_local: bool) -> void:
	if slot < 0 or slot >= factory_slot_centers.size():
		return
	factory_peer_slots[peer_id] = slot
	var plot: Node3D = factory_plots[slot]
	plot.set_meta("owner_peer_id", peer_id)
	plot.set_meta("owner_company", owner_company)
	plot.set_meta("is_local_owner", is_local)
	var sign_label := plot.get_meta("sign_label") as Label3D
	if sign_label:
		sign_label.text = owner_company
		sign_label.modulate = brand_color if is_local else Color("#6cb9ff")
	var terminals: Array = factory_slot_terminals.get(slot, [])
	for terminal in terminals:
		if is_local:
			terminal.set_meta("kind", str(terminal.get_meta("factory_role")))
			terminal.set_meta("title", str(terminal.get_meta("factory_title")))
		else:
			terminal.set_meta("kind", "rival_factory")
			terminal.set_meta("title", "VISIT " + owner_company)

func _release_factory_owner(peer_id: int) -> void:
	if not factory_peer_slots.has(peer_id):
		return
	var slot := int(factory_peer_slots[peer_id])
	factory_peer_slots.erase(peer_id)
	if slot < 0 or slot >= factory_plots.size():
		return
	var plot: Node3D = factory_plots[slot]
	plot.set_meta("owner_peer_id", 0)
	plot.set_meta("owner_company", "AVAILABLE FACTORY")
	plot.set_meta("is_local_owner", false)
	var sign_label := plot.get_meta("sign_label") as Label3D
	if sign_label:
		sign_label.text = "AVAILABLE FACTORY"
		sign_label.modulate = Color("#6cb9ff")
	for terminal in factory_slot_terminals.get(slot, []):
		terminal.set_meta("kind", "rival_factory")
		terminal.set_meta("title", "UNASSIGNED FACTORY")

func _assign_local_factory(slot: int) -> void:
	if slot < 0 or slot >= factory_slot_centers.size():
		return
	local_factory_slot = slot
	_assign_factory_owner(online_peer_id, slot, company_name, true)
	var center := factory_slot_centers[slot]
	player.global_position = center + Vector3(-10, 0.1, -48)
	starter_vehicle.global_position = center + Vector3(10, 0.1, -48)
	starter_vehicle.rotation.y = PI
	for index in range(manufactured_vehicles.size()):
		var vehicle := manufactured_vehicles[index]
		if is_instance_valid(vehicle):
			vehicle.global_position = _factory_parking_position(index)
			vehicle.rotation.y = PI

func _factory_parking_position(index: int) -> Vector3:
	if local_factory_slot >= 0 and local_factory_slot < factory_slot_centers.size():
		var center := factory_slot_centers[local_factory_slot]
		return center + Vector3(-24.0 + (index % 3) * 24.0, 0.1, 34.0 + (index / 3) * 9.0)
	return Vector3(60 + (index % 3) * 20.0, 0.1, 51 + (index / 3) * 10.0)

func _build_clean_dealership() -> void:
	var center := Vector3(0, 0, 80)
	_clean_lot(center, Vector3(56, 0, 60), Color("#aeb5b6"))
	_building(Vector3(0, 5.5, 89), Vector3(46, 11, 40), Color("#eef1f2"))
	_sign(Vector3(0, 10.2, 68.4), "EMPIRE AUTO", Color("#42dda4"))
	_terminal(Vector3(0, 1.1, 61), "dealership", "SELL VEHICLES", Color("#35d59b"))
	_sign(Vector3(0, 7.0, 110), "DEALERSHIP", Color("#63e0b2"))

func _build_clean_suppliers() -> void:
	var shops := [
		[Vector3(178, 0, -80), "APEX ENGINES", "engine_shop", Color("#ef655f")],
		[Vector3(178, 0, 0), "METRO CHASSIS", "chassis_shop", Color("#58acff")],
		[Vector3(178, 0, 80), "VOLT LABS", "electronics_shop", Color("#aa72ff")],
	]
	for data in shops:
		var center: Vector3 = data[0]
		_clean_lot(center, Vector3(82, 0, 62), Color("#9ca3a5"))
		_building(center + Vector3(0, 5.5, 5), Vector3(66, 11, 38), data[3].lightened(0.58))
		_sign(center + Vector3(0, 9.2, -14.3), data[1], data[3])
		_terminal(center + Vector3(0, 1.1, -22), data[2], "SHOP", data[3])
	_sign(Vector3(178, 7, 110), "SUPPLIER DISTRICT", Color("#6fc3ff"))

func _build_clean_landmarks() -> void:
	_build_burger_drive(Vector3(80, 0, -80))
	_build_clinic(Vector3(80, 0, 0))
	_build_fire_station(Vector3(80, 0, -179))
	_build_fuel_station(Vector3(179, 0, -179))
	_build_shopping_center(Vector3(-80, 0, -179))
	_build_city_hotel(Vector3(0, 0, 179))
	_build_car_wash(Vector3(-80, 0, 179))

func _build_clean_street_props() -> void:
	_build_bus_shelter(Vector3(178, 0, -50), PI)
	for pos in [Vector3(30, 0, 30), Vector3(-30, 0, -30), Vector3(130, 0, 30), Vector3(-130, 0, -30)]:
		_build_hydrant(pos)
	for pos in [Vector3(-27, 0, 105), Vector3(105, 0, -27), Vector3(133, 0, 105)]:
		_build_trash_bin(pos)

func _build_bus_shelter(pos: Vector3, yaw_value: float) -> void:
	var shelter := Node3D.new()
	shelter.position = pos
	shelter.rotation.y = yaw_value
	add_child(shelter)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.25, 0.65, 0.78, 0.48)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.12
	for x in [-3.0, 3.0]:
		var panel := MeshInstance3D.new()
		var panel_mesh := BoxMesh.new()
		panel_mesh.size = Vector3(0.12, 4.2, 3.0)
		panel.mesh = panel_mesh
		panel.position = Vector3(x, 2.1, 0)
		panel.material_override = glass
		shelter.add_child(panel)
	var back := MeshInstance3D.new()
	var back_mesh := BoxMesh.new()
	back_mesh.size = Vector3(6.0, 4.2, 0.12)
	back.mesh = back_mesh
	back.position = Vector3(0, 2.1, 1.45)
	back.material_override = glass
	shelter.add_child(back)
	_local_box(shelter, Vector3(0, 4.4, 0), Vector3(7.0, 0.35, 3.5), Color("#247f9c"))
	_local_box(shelter, Vector3(0, 1.1, 0.5), Vector3(4.8, 0.25, 1.0), Color("#454f55"))
	_local_box(shelter, Vector3(-2.8, 3.1, -1.6), Vector3(1.0, 2.2, 0.15), Color("#f0bd3d"))

func _local_box(parent: Node3D, pos: Vector3, size: Vector3, color: Color) -> void:
	var instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	instance.mesh = mesh
	instance.position = pos
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.75
	instance.material_override = material
	parent.add_child(instance)

func _build_bench(pos: Vector3) -> void:
	var wood := Color("#8a5738")
	var metal := Color("#354149")
	_box("BenchSeat", pos + Vector3(0, 0.75, 0), Vector3(3.8, 0.28, 1.0), wood, false)
	_box("BenchBack", pos + Vector3(0, 1.45, 0.42), Vector3(3.8, 1.0, 0.22), wood, false)
	for x in [-1.45, 1.45]:
		_box("BenchLeg", pos + Vector3(x, 0.38, 0), Vector3(0.22, 0.75, 0.65), metal, false)

func _build_hydrant(pos: Vector3) -> void:
	_box("HydrantBody", pos + Vector3(0, 0.62, 0), Vector3(0.55, 1.15, 0.55), Color("#d94b3f"), false)
	_box("HydrantTop", pos + Vector3(0, 1.25, 0), Vector3(0.8, 0.22, 0.8), Color("#f1c24c"), false)
	_box("HydrantArm", pos + Vector3(0, 0.72, 0), Vector3(1.1, 0.3, 0.3), Color("#d94b3f"), false)

func _build_trash_bin(pos: Vector3) -> void:
	_box("TrashBin", pos + Vector3(0, 0.7, 0), Vector3(1.1, 1.4, 1.1), Color("#3d655b"), false)
	_box("TrashLid", pos + Vector3(0, 1.45, 0), Vector3(1.25, 0.18, 1.25), Color("#263e39"), false)

func _add_tower_architecture(center: Vector3, footprint: Vector3, height: float, accent: Color) -> void:
	# Vertical fins, a framed entrance and side glazing break up the plain boxes.
	for side in [-1.0, 1.0]:
		_box("TowerFin", Vector3(center.x + side * footprint.x * 0.43, height * 0.5, center.z - footprint.z * 0.505), Vector3(0.75, height * 0.92, 0.34), accent, false)
		_box("SideGlass", Vector3(center.x + side * footprint.x * 0.505, height * 0.54, center.z), Vector3(0.2, height * 0.58, footprint.z * 0.56), Color("#47788f"), false)
	_box("EntranceFrame", Vector3(center.x, 2.8, center.z - footprint.z * 0.515), Vector3(8.0, 5.6, 0.5), accent, false)
	_box("EntranceGlass", Vector3(center.x, 2.5, center.z - footprint.z * 0.53), Vector3(5.2, 4.2, 0.22), Color("#8ed9e8"), false)
	_box("EntranceCanopy", Vector3(center.x, 5.7, center.z - footprint.z * 0.58), Vector3(11, 0.38, 3.8), accent.lightened(0.15), false)

func _build_burger_drive(center: Vector3) -> void:
	_clean_lot(center, Vector3(60, 0, 60), Color("#575c5c"))
	var cream := Color("#f2d9a9")
	var red := Color("#c83d32")
	var yellow := Color("#f3be32")
	_building(center + Vector3(-4, 3.7, 4), Vector3(40, 7.4, 30), cream)
	_box("DriveCanopy", center + Vector3(21, 4.2, 5), Vector3(11, 0.7, 25), red, false)
	_box("DrivePost", center + Vector3(25, 2.0, -5), Vector3(0.6, 4.0, 0.6), red, false)
	_box("DrivePost", center + Vector3(25, 2.0, 15), Vector3(0.6, 4.0, 0.6), red, false)
	_box("FoodSignPost", center + Vector3(-24, 5.0, -20), Vector3(0.7, 10, 0.7), Color("#40484d"), false)
	_box("FoodSign", center + Vector3(-24, 9.0, -20), Vector3(8.5, 4.2, 0.8), red, false)
	_sign(center + Vector3(-24, 9.0, -20.5), "B", yellow)
	_sign(center + Vector3(-4, 7.4, -11.6), "BURGER DRIVE", yellow)

func _build_clinic(center: Vector3) -> void:
	_clean_lot(center, Vector3(60, 0, 60), Color("#8d9699"))
	_building(center + Vector3(-8, 6.0, 3), Vector3(39, 12, 42), Color("#dce8e8"))
	_building(center + Vector3(17, 4.0, 8), Vector3(16, 8, 28), Color("#bcd7d9"))
	_box("ClinicCrossV", center + Vector3(8, 8.7, -18.55), Vector3(1.1, 5.0, 0.28), Color("#e95757"), false)
	_box("ClinicCrossH", center + Vector3(8, 8.7, -18.58), Vector3(5.0, 1.1, 0.3), Color("#e95757"), false)
	_sign(center + Vector3(-8, 10.4, -18.6), "CITY CLINIC", Color("#71e3dc"))

func _build_fire_station(center: Vector3) -> void:
	_clean_lot(center, Vector3(60, 0, 94), Color("#777d7d"))
	var brick := Color("#a64b3c")
	var dark_red := Color("#7e2f29")
	_building(center + Vector3(0, 5.5, 8), Vector3(55, 11, 48), brick)
	_building(center + Vector3(19, 10, 25), Vector3(13, 20, 13), dark_red)
	_sign(center + Vector3(0, 10.0, -16.7), "FIRE & RESCUE", Color("#ffd06a"))

func _build_fuel_station(center: Vector3) -> void:
	_clean_lot(center, Vector3(94, 0, 94), Color("#676d6d"))
	var navy := Color("#174a78")
	var orange := Color("#ef7f32")
	_building(center + Vector3(25, 3.5, 23), Vector3(35, 7, 27), Color("#d8e1e3"))
	_box("FuelCanopy", center + Vector3(-12, 5.0, -5), Vector3(58, 1.0, 30), navy, false)
	for x in [-30.0, 5.0]:
		for z in [-14.0, 5.0]:
			_box("CanopyPost", center + Vector3(x, 2.5, z), Vector3(0.7, 5.0, 0.7), Color("#d5dcdd"), false)
	for x in [-22.0, -3.0]:
		_box("FuelPump", center + Vector3(x, 1.2, -5), Vector3(2.2, 2.4, 1.5), orange, false)
	_sign(center + Vector3(25, 7.0, 9), "NORTHSTAR FUEL", Color("#72cbff"))

func _build_shopping_center(center: Vector3) -> void:
	_clean_lot(center, Vector3(60, 0, 94), Color("#969b99"))
	var sand := Color("#d7bf96")
	_building(center + Vector3(0, 5.0, 10), Vector3(57, 10, 48), sand)
	_sign(center + Vector3(0, 9, -14.7), "MARKET HALL", Color("#d6ffd5"))

func _build_city_hotel(center: Vector3) -> void:
	_clean_lot(center, Vector3(60, 0, 94), Color("#999c99"))
	var cream := Color("#eadbc5")
	_building(center + Vector3(0, 12, 5), Vector3(45, 24, 54), cream)
	_sign(center + Vector3(0, 23, -23), "THE FOUNDRY HOTEL", Color("#ffe2a3"))

func _build_car_wash(center: Vector3) -> void:
	_clean_lot(center, Vector3(60, 0, 94), Color("#717777"))
	var white := Color("#e5edef")
	_building(center + Vector3(0, 4.2, 8), Vector3(52, 8.4, 42), white)
	_sign(center + Vector3(0, 10, -14), "SPLASH AUTO WASH", Color("#8cedff"))

func _build_clean_residential() -> void:
	var positions := [
		Vector3(-205, 0, -95), Vector3(-162, 0, -95),
		Vector3(-205, 0, -55), Vector3(-162, 0, -55),
		Vector3(-205, 0, -15), Vector3(-162, 0, -15),
		Vector3(-205, 0, 70), Vector3(-162, 0, 70),
	]
	var models := ["building-a", "building-c", "building-h", "building-i", "building-b", "building-k", "building-l", "building-m"]
	for i in range(positions.size()):
		var path: String = "res://assets/city/kenney/" + str(models[i]) + ".glb"
		_spawn_city_model(path, positions[i], 10.0, PI if i % 2 == 0 else 0.0, Vector3(12, 18, 12))
		_box("GardenHedge", positions[i] + Vector3(0, 0.6, -8), Vector3(11, 1.2, 0.8), Color("#27884c"), false)
	_sign(Vector3(-180, 7, 30), "MAPLE HEIGHTS", Color("#ffe08a"))

func _build_clean_park() -> void:
	var center := Vector3(-80, 0, 80)
	_clean_lot(center, Vector3(60, 0, 60), Color("#58a65d"))
	_box("ParkPath", Vector3(-80, 0.02, 80), Vector3(7, 0.02, 58), Color("#dccba5"), false)
	_box("ParkPath", Vector3(-80, 0.021, 80), Vector3(58, 0.02, 7), Color("#dccba5"), false)
	var tree_positions := [
		Vector3(-110, 0, 52), Vector3(-96, 0, 61), Vector3(-55, 0, 54),
		Vector3(-105, 0, 102), Vector3(-57, 0, 108), Vector3(-60, 0, 82),
	]
	for p in tree_positions:
		_tree(p)
	_spawn_city_model("res://assets/city/kenney/detail-parasol-a.glb", Vector3(-72, 0, 72), 5.0, 0.0)
	_spawn_city_model("res://assets/city/kenney/detail-parasol-b.glb", Vector3(-90, 0, 92), 5.0, PI * 0.4)
	_sign(Vector3(-80, 6, 80), "FOUNDERS PARK", Color("#b8ffbd"))

func _build_clean_airport() -> void:
	var center := Vector3(179, 0, 179)
	_clean_lot(center, Vector3(94, 0, 94), Color("#747d82"))
	_box("Runway", Vector3(179, 0.015, 202), Vector3(88, 0.025, 22), Color("#2c3237"), false)
	for x in range(142, 217, 13):
		_box("RunwayMark", Vector3(x, 0.034, 202), Vector3(6, 0.012, 0.45), Color("#f1f1eb"), false)
	_building(Vector3(179, 5.5, 157), Vector3(78, 11, 25), Color("#d9b2a9"))
	_building(Vector3(214, 12, 171), Vector3(10, 24, 10), Color("#b88677"))
	_sign(Vector3(179, 10.0, 139.8), "EMPIRE AIR CARGO", Color("#70dcff"))
	_terminal(Vector3(179, 1.1, 139), "airport_cargo", "AIR CARGO", Color("#65d3ff"))

func _build_clean_harbor() -> void:
	# Harbor remains inside its own southwest block and never intersects a road.
	_box("HarborWater", Vector3(-181, -0.015, 185), Vector3(94, 0.025, 82), Color("#287ea6"), false)
	_box("Dock", Vector3(-181, 0.02, 146), Vector3(88, 0.12, 16), Color("#777c7d"), false)
	for i in range(12):
		var x := -218.0 + float(i % 4) * 18.0
		var z := 145.0 + float(i / 4) * 7.0
		var colors := [Color("#dc5548"), Color("#397faf"), Color("#dba83a")]
		_box("Container", Vector3(x, 1.5, z), Vector3(14, 2.8, 5.0), colors[i % colors.size()], false)
	_building(Vector3(-181, 5.5, 217), Vector3(72, 11, 19), Color("#c8ced0"))
	_sign(Vector3(-181, 10.0, 207), "PORT EMPIRE", Color("#63def1"))
	_terminal(Vector3(-181, 1.1, 205), "dock_imports", "IMPORT TERMINAL", Color("#f3b947"))
	# Grounded waterfront architecture replaces the disconnected bridge.
	_box("QuayWall", Vector3(-181, 1.1, 183), Vector3(96, 2.2, 2.0), Color("#6e7478"), false)
	_box("Promenade", Vector3(-181, 0.05, 174), Vector3(96, 0.12, 16), Color("#b7b4aa"), false)
	for x in range(-220, -140, 10):
		_box("RailingPost", Vector3(x, 1.0, 181.7), Vector3(0.15, 2.0, 0.15), Color("#45525a"), false)
	_box("Railing", Vector3(-181, 1.7, 181.7), Vector3(88, 0.15, 0.15), Color("#45525a"), false)
	for x in [-214.0, -190.0, -166.0, -142.0]:
		_clean_street_lamp(Vector3(x, 0, 170))
	_box("CargoCraneLeg", Vector3(-218, 9, 154), Vector3(2.0, 18, 2.0), Color("#d4a230"), false)
	_box("CargoCraneArm", Vector3(-203, 17, 154), Vector3(32, 1.8, 1.8), Color("#d4a230"), false)

func _build_harbor_bridge() -> void:
	var steel := Color("#59616d")
	var deck := _box("BridgeDeck", Vector3(-181, 3.4, 184), Vector3(96, 1.1, 15), Color("#343b42"), false)
	deck.rotation.y = 0.0
	for z in [178.0, 190.0]:
		var previous := Vector3(-227, 4.2, z)
		for i in range(1, 13):
			var t := float(i) / 12.0
			var point := Vector3(lerpf(-227, -135, t), 4.2 + sin(t * PI) * 15.0, z)
			_bridge_beam(previous, point, 0.75, steel)
			if i % 2 == 0:
				_box("BridgeHanger", Vector3(point.x, (point.y + 4.2) * 0.5, z), Vector3(0.3, point.y - 4.2, 0.3), steel, false)
			previous = point
	for x in range(-222, -137, 12):
		_box("BridgeCrossbeam", Vector3(x, 4.4, 184), Vector3(0.35, 0.35, 13), steel, false)
	for x in range(-220, -140, 16):
		_box("BridgeMark", Vector3(x, 4.0, 184), Vector3(7.0, 0.05, 0.22), Color("#efca42"), false)

func _bridge_beam(a: Vector3, b: Vector3, thickness: float, color: Color) -> void:
	var midpoint := (a + b) * 0.5
	var delta := b - a
	var beam := _box("BridgeArch", midpoint, Vector3(delta.length(), thickness, thickness), color, false)
	beam.rotation.z = atan2(delta.y, delta.x)

func _low_poly_rock(pos: Vector3, scale_value: Vector3) -> void:
	var rock := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	mesh.radial_segments = 6
	mesh.rings = 3
	rock.mesh = mesh
	rock.position = pos
	rock.scale = scale_value
	rock.rotation = Vector3(0.12, pos.x * 0.08, 0.08)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#777279")
	material.roughness = 0.95
	rock.material_override = material
	add_child(rock)

func _build_clean_power_plant() -> void:
	var center := Vector3(176, 0, 258)
	_clean_lot(center, Vector3(104, 0, 36), Color("#697174"))
	_building(Vector3(218, 6, 258), Vector3(36, 12, 30), Color("#88939c"))
	_cooling_tower(Vector3(145, 0, 258), 18.0)
	_cooling_tower(Vector3(173, 0, 258), 22.0)
	for x in [205.0, 216.0, 227.0]:
		var stack := MeshInstance3D.new()
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = 1.4
		cylinder.bottom_radius = 1.8
		cylinder.height = 29.0
		stack.mesh = cylinder
		stack.position = Vector3(x, 14.5, 267)
		var stack_material := StandardMaterial3D.new()
		stack_material.albedo_color = Color("#8b5550")
		stack.material_override = stack_material
		add_child(stack)
		_box("StackBand", Vector3(x, 22, 267), Vector3(3.8, 1.0, 3.8), Color("#e6ded4"), false)
	_sign(Vector3(186, 13, 239), "EMPIRE ENERGY", Color("#ffd267"))

func _cooling_tower(pos: Vector3, height: float) -> void:
	var tower := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = height * 0.28
	mesh.bottom_radius = height * 0.43
	mesh.height = height
	mesh.radial_segments = 12
	tower.mesh = mesh
	tower.position = pos + Vector3(0, height * 0.5, 0)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#b0aaa6")
	material.roughness = 0.92
	tower.material_override = material
	add_child(tower)
	var rim := MeshInstance3D.new()
	var rim_mesh := TorusMesh.new()
	rim_mesh.inner_radius = height * 0.255
	rim_mesh.outer_radius = height * 0.305
	rim_mesh.rings = 12
	rim_mesh.ring_segments = 6
	rim.mesh = rim_mesh
	rim.position = pos + Vector3(0, height, 0)
	rim.material_override = material
	add_child(rim)

func _build_clean_border() -> void:
	# Mountains are outside the town boundary. No scenery is generated randomly.
	for i in range(10):
		var x := -250.0 + i * 55.0
		_mountain(Vector3(x, 0, -270), 28.0 + float((i * 11) % 20))
	# A few entrance signs and no roadside trees.
	_sign(Vector3(0, 9, -224), "WELCOME TO EMPIRE CITY", Color("#f5e7a4"))

func _build_outer_city() -> void:
	_build_city_grid()
	_build_highway_ring()
	_build_airport()
	_build_docks()
	_build_suburbs()
	_build_luxury_ridge()
	_build_mountain_country()

func _build_city_grid() -> void:
	# Secondary streets turn the original three-road cross into a navigable city.
	for z in [-150.0, -120.0, -90.0, 90.0, 120.0, 150.0]:
		_road(Vector3(0, 0.025, z), Vector3(330, 0.09, 11))
	for x in [-150.0, -120.0, -60.0, 60.0, 120.0, 150.0]:
		_road(Vector3(x, 0.03, 0), Vector3(11, 0.1, 330))
	# Crosswalks make the core intersections visually readable at speed.
	for x in [-90.0, 0.0, 90.0]:
		for z in [-60.0, 0.0, 60.0]:
			for stripe in range(-4, 5):
				_box("Crosswalk", Vector3(x + stripe * 1.25, -0.003, z - 8.1), Vector3(0.62, 0.012, 3.2), Color("#f2f3ee"), false)
				_box("Crosswalk", Vector3(x - 8.1, -0.002, z + stripe * 1.25), Vector3(3.2, 0.012, 0.62), Color("#f2f3ee"), false)
			_traffic_lights(Vector3(x + 10.1, 0, z + 10.1))
	# Infill: a dense but varied central skyline.
	var blocks := [
		[Vector3(-74, 0, -44), Vector3(20, 0, 20), 28.0, Color("#d7e1e8")],
		[Vector3(-45, 0, -43), Vector3(22, 0, 22), 19.0, Color("#e7c9af")],
		[Vector3(-74, 0, 37), Vector3(20, 0, 24), 38.0, Color("#9db6c8")],
		[Vector3(-42, 0, 37), Vector3(23, 0, 22), 25.0, Color("#d9ddd7")],
		[Vector3(39, 0, -39), Vector3(22, 0, 23), 31.0, Color("#b4c9d6")],
		[Vector3(73, 0, -41), Vector3(20, 0, 22), 22.0, Color("#e3d2bc")],
		[Vector3(42, 0, 39), Vector3(23, 0, 21), 18.0, Color("#bdcbd1")],
		[Vector3(74, 0, 39), Vector3(20, 0, 23), 34.0, Color("#dce3e8")],
	]
	for data in blocks:
		var p: Vector3 = data[0]
		var footprint: Vector3 = data[1]
		var height: float = data[2]
		_building(Vector3(p.x, height * 0.5, p.z), Vector3(footprint.x, height, footprint.z), data[3])
		_rooftop_detail(Vector3(p.x, height, p.z), footprint)
	# A green civic square creates a landmark in the dense core.
	_box("CivicPark", Vector3(16, 0.055, -25), Vector3(21, 0.12, 30), Color("#55a963"), false)
	_box("ParkPath", Vector3(16, 0.125, -25), Vector3(3.0, 0.03, 30), Color("#d7c8a8"), false)
	_sign(Vector3(16, 4.3, -25), "EMPIRE SQUARE", Color("#8bf0bd"))

func _build_highway_ring() -> void:
	var points: Array[Vector3] = []
	var segments := 72
	for i in range(segments):
		var angle := TAU * float(i) / float(segments)
		points.append(Vector3(cos(angle) * 255.0, 1.25, sin(angle) * 220.0))
	for i in range(segments):
		var a := points[i]
		var b := points[(i + 1) % segments]
		_road_segment(a, b, 18.0, Color("#2d343b"), true)
		_road_segment(a + Vector3(0, 0.09, 0), b + Vector3(0, 0.09, 0), 0.22, Color("#f3d33f"), false)
	# Long connectors and raised flyovers lead naturally from the city grid.
	_road_segment(Vector3(0, 0.03, -158), Vector3(0, 1.25, -220), 18.0, Color("#30373e"), true)
	_road_segment(Vector3(0, 0.03, 158), Vector3(0, 1.25, 220), 18.0, Color("#30373e"), true)
	_road_segment(Vector3(-158, 0.03, 0), Vector3(-255, 1.25, 0), 18.0, Color("#30373e"), true)
	_road_segment(Vector3(158, 0.03, 0), Vector3(255, 1.25, 0), 18.0, Color("#30373e"), true)
	for x in [-6.0, 6.0]:
		_road_segment(Vector3(x, 0.36, -158), Vector3(x, 1.36, -220), 0.18, Color("#f6f6ef"), false)
		_road_segment(Vector3(x, 0.36, 158), Vector3(x, 1.36, 220), 0.18, Color("#f6f6ef"), false)
	# Curving access ramps near the factory and dealership.
	_build_curve_road(Vector3(90, 0, 110), Vector3(178, 0, 181), 34.0, false)
	_build_curve_road(Vector3(-90, 0, 110), Vector3(-178, 0, 181), -34.0, false)
	_sign(Vector3(0, 9, -214), "EMPIRE EXPRESSWAY", Color("#64d5ff"))

func _build_curve_road(start: Vector3, finish: Vector3, bend: float, raised: bool) -> void:
	var previous := start
	var steps := 16
	for i in range(1, steps + 1):
		var t := float(i) / float(steps)
		var point := start.lerp(finish, t)
		point.x += sin(t * PI) * bend
		if raised:
			point.y = 1.5 + sin(t * PI) * 4.0
		else:
			point.y = lerpf(0.15, 1.15, t)
		_road_segment(previous, point, 13.0, Color("#30373e"), true)
		previous = point

func _build_airport() -> void:
	var center := Vector3(185, 0, 155)
	_box("AirportApron", center + Vector3(0, 0.03, 7), Vector3(112, 0.08, 88), Color("#6f787e"), true)
	_box("Runway", Vector3(190, 0.09, 247), Vector3(245, 0.12, 29), Color("#292f35"), true)
	for x in range(82, 303, 18):
		_box("RunwayMark", Vector3(x, 0.17, 247), Vector3(8, 0.025, 0.7), Color("#f1f1e9"), false)
	for z in [235.0, 259.0]:
		for x in range(72, 310, 10):
			var lamp := OmniLight3D.new()
			lamp.position = Vector3(x, 0.5, z)
			lamp.light_color = Color("#72c9ff")
			lamp.light_energy = 1.4
			lamp.omni_range = 4.0
			add_child(lamp)
	_building(center + Vector3(-24, 8, -26), Vector3(62, 16, 24), Color("#dce4e7"))
	_box("TerminalGlass", center + Vector3(-24, 7, -38.2), Vector3(52, 9, 0.25), Color(0.1, 0.38, 0.58, 0.82), false)
	_building(center + Vector3(41, 11, -23), Vector3(18, 22, 18), Color("#c9d3d9"))
	_box("ControlCab", center + Vector3(41, 24, -23), Vector3(25, 5, 25), Color("#41677d"), false)
	_sign(center + Vector3(-24, 15, -39), "EMPIRE INTERNATIONAL", Color("#74dcff"))
	_terminal(center + Vector3(-24, 1.1, -43), "airport_cargo", "AIR CARGO", Color("#65d3ff"))
	# Simple parked aircraft silhouette.
	_box("AircraftBody", Vector3(195, 2.0, 172), Vector3(4.2, 3.0, 36), Color("#f2f4f6"), false)
	_box("AircraftWing", Vector3(195, 2.0, 174), Vector3(30, 0.55, 8), Color("#e2e8ec"), false)
	_sign(Vector3(185, 7, 115), "AIRPORT DISTRICT", Color("#75dfff"))

func _build_docks() -> void:
	_box("HarborWater", Vector3(-230, -0.18, 206), Vector3(205, 0.35, 115), Color("#267aa7"), false)
	for x in [-286.0, -248.0, -210.0, -172.0]:
		_box("Pier", Vector3(x, 0.1, 172), Vector3(23, 0.55, 70), Color("#777b7b"), true)
	for i in range(22):
		var x := -302.0 + float(i % 6) * 12.0
		var z := 145.0 + float(i / 6) * 9.0
		var colors := [Color("#dc4f42"), Color("#337fb8"), Color("#e1a935"), Color("#42986a")]
		_box("Container", Vector3(x, 1.65, z), Vector3(10, 3.1, 4.6), colors[i % colors.size()], false)
	_building(Vector3(-175, 7, 132), Vector3(58, 14, 34), Color("#bdc4c7"))
	_box("CranePost", Vector3(-251, 11, 173), Vector3(2.5, 22, 2.5), Color("#e1ae32"), false)
	_box("CraneArm", Vector3(-237, 21, 173), Vector3(30, 2.1, 2.1), Color("#e1ae32"), false)
	_sign(Vector3(-209, 9, 123), "PORT EMPIRE", Color("#53d9f4"))
	_terminal(Vector3(-174, 1.1, 113), "dock_imports", "IMPORT TERMINAL", Color("#f3b947"))

func _build_suburbs() -> void:
	# Residential loops east of downtown.
	_road_segment(Vector3(171, 0.05, -150), Vector3(245, 0.2, -150), 11.0, Color("#3b4247"), true)
	_road_segment(Vector3(171, 0.05, -90), Vector3(245, 0.2, -90), 11.0, Color("#3b4247"), true)
	_road_segment(Vector3(185, 0.05, -171), Vector3(185, 0.15, -70), 11.0, Color("#3b4247"), true)
	_road_segment(Vector3(225, 0.05, -171), Vector3(225, 0.15, -70), 11.0, Color("#3b4247"), true)
	var house_colors := [Color("#f0d1a9"), Color("#bdd5de"), Color("#d8b8c5"), Color("#d8dfbd")]
	var house_index := 0
	for x in [170.0, 201.0, 241.0]:
		for z in [-166.0, -132.0, -108.0, -75.0]:
			_house(Vector3(x, 0, z), house_colors[house_index % house_colors.size()])
			house_index += 1
	_sign(Vector3(208, 7, -118), "SUNSET HEIGHTS", Color("#f2d277"))

func _build_luxury_ridge() -> void:
	# A coastal/luxury neighborhood on the western hill.
	_road_segment(Vector3(-170, 0.1, -150), Vector3(-245, 3.0, -150), 12.0, Color("#363d43"), true)
	_road_segment(Vector3(-245, 3.0, -150), Vector3(-250, 6.0, -75), 12.0, Color("#363d43"), true)
	for i in range(5):
		var z := -145.0 + i * 17.0
		_box("VillaTerrace", Vector3(-220, 2.0 + i * 0.7, z), Vector3(28, 0.8, 14), Color("#7ba365"), true)
		_building(Vector3(-220, 5.0 + i * 0.7, z), Vector3(21, 6, 10), Color("#f0eee6"))
		_box("VillaGlass", Vector3(-209.4, 5.2 + i * 0.7, z), Vector3(0.22, 3.5, 7.5), Color(0.12, 0.42, 0.59, 0.75), false)
	_sign(Vector3(-223, 11, -109), "AZURE RIDGE", Color("#cfb8ff"))
	_terminal(Vector3(-245, 4.1, -112), "custom_shop", "CUSTOMS ATELIER", Color("#c486ff"))

func _build_mountain_country() -> void:
	for i in range(14):
		var x := -315.0 + i * 48.0
		var height := 32.0 + fmod(float(i * 17), 34.0)
		_mountain(Vector3(x, 0, -315 + fmod(float(i * 29), 45.0)), height)
	# A winding northern road through the hills.
	var previous := Vector3(-252, 1.0, -220)
	for i in range(1, 25):
		var t := float(i) / 24.0
		var point := Vector3(lerpf(-252, 252, t), 1.0 + sin(t * PI) * 5.0, -232.0 - sin(t * TAU * 2.0) * 22.0)
		_road_segment(previous, point, 11.0, Color("#343b40"), true)
		previous = point
	_sign(Vector3(0, 15, -267), "NORTH RIDGE PASS", Color("#e9dfad"))

func _build_downtown() -> void:
	var colors := [Color("#d9e2ea"), Color("#acc5d8"), Color("#e8d7bc"), Color("#9fb4c3")]
	for x in [-140.0, -117.0, -66.0, -39.0, 39.0, 66.0]:
		for z in [-142.0, -116.0]:
			var h := 18.0 + fmod(abs(x + z), 24.0)
			_building(Vector3(x, h / 2.0, z), Vector3(17, h, 17), colors[int(abs(x + z)) % colors.size()])
	_sign(Vector3(-90, 7.0, -90), "DOWNTOWN", Color("#2a9df4"))

func _build_industrial() -> void:
	_building(Vector3(42, 7, 105), Vector3(50, 14, 37), Color("#d7dde2"))
	_box("FactoryStripe", Vector3(42, 8.0, 85.95), Vector3(50.2, 2.0, 0.3), brand_color, false)
	_sign(Vector3(42, 12.2, 84.8), "YOUR FACTORY", Color("#ff7b35"))
	_terminal(Vector3(18, 1.1, 82), "factory", "ASSEMBLY LINE", Color("#ff8a38"))
	_terminal(Vector3(41, 1.1, 82), "storage", "PARTS STORAGE", Color("#39c7ff"))
	_terminal(Vector3(64, 1.1, 82), "design", "DESIGN STUDIO", Color("#b87cff"))
	# Loading bay decoration
	for x in [26.0, 38.0, 50.0]:
		_box("Bay", Vector3(x, 3.0, 85.7), Vector3(8.5, 5.2, 0.35), Color("#273444"), false)
	_sign(Vector3(90, 7.0, 90), "INDUSTRIAL DISTRICT", Color("#ff9d47"))

func _build_dealership() -> void:
	_building(Vector3(-42, 6, 105), Vector3(48, 12, 36), Color("#f2f5f7"))
	_box("Glass", Vector3(-42, 5.2, 86.85), Vector3(40, 7.2, 0.28), Color(0.16, 0.48, 0.68, 0.72), false)
	_sign(Vector3(-42, 11.3, 85.9), "EMPIRE AUTO GALLERY", Color("#34d49a"))
	_terminal(Vector3(-42, 1.1, 80), "dealership", "SELL VEHICLES", Color("#35d59b"))
	_sign(Vector3(-90, 7.0, 90), "DEALERSHIP ROW", Color("#36d49a"))

func _build_suppliers() -> void:
	var shops := [
		[Vector3(124, 5, 39), "APEX ENGINES", "engine_shop", Color("#ef5b5b")],
		[Vector3(124, 5, -39), "METRO CHASSIS", "chassis_shop", Color("#4ca6ff")],
		[Vector3(124, 5, -105), "VOLT LABS", "electronics_shop", Color("#a56cff")],
	]
	for data in shops:
		var p: Vector3 = data[0]
		_building(p, Vector3(42, 10, 28), Color("#e7eaee"))
		_sign(p + Vector3(0, 4.0, -14.2), data[1], data[3])
		_terminal(p + Vector3(0, -3.9, -16.0), data[2], "SHOP", data[3])
	_sign(Vector3(90, 7.0, 0), "SUPPLIER AVENUE", Color("#4ca6ff"))

func _build_track() -> void:
	# Stylized oval circuit in the west.
	var center := Vector3(-118, 0.04, 15)
	for i in range(64):
		var angle := TAU * float(i) / 64.0
		var p := center + Vector3(cos(angle) * 36.0, 0, sin(angle) * 23.0)
		var segment := _box("Track", p, Vector3(7.5, 0.08, 10.0), Color("#323940"), false)
		segment.rotation.y = -angle
	_terminal(Vector3(-118, 1.1, 15), "race", "TEST TRACK", Color("#f4cc45"))
	_sign(Vector3(-118, 5.0, 15), "R&D TEST CIRCUIT", Color("#f4cc45"))

func _build_scenery() -> void:
	for i in range(90):
		var angle := float(i) * 2.399
		var radius := 75.0 + fmod(float(i * 31), 85.0)
		var p := Vector3(cos(angle) * radius, 0, sin(angle) * radius)
		if abs(p.x) < 15 or abs(p.z) < 15:
			continue
		if (p - Vector3(42, 0, 105)).length() < 38 or (p - Vector3(-42, 0, 105)).length() < 35:
			continue
		_tree(p)
	for z in [-145.0, -75.0, 75.0, 145.0]:
		for x in [-145.0, -75.0, 75.0, 145.0]:
			_box("LampPole", Vector3(x, 2.8, z), Vector3(0.18, 5.6, 0.18), Color("#29394a"), false)
			var lamp := OmniLight3D.new()
			lamp.position = Vector3(x, 5.5, z)
			lamp.light_color = Color("#ffe1a6")
			lamp.light_energy = 2.0
			lamp.omni_range = 13.0
			add_child(lamp)

func _road_segment(a: Vector3, b: Vector3, width: float, color: Color, collision: bool) -> Node3D:
	var midpoint := (a + b) * 0.5
	var length := Vector2(b.x - a.x, b.z - a.z).length()
	var is_raised := a.y > 0.35 or b.y > 0.35
	var thickness := 0.16 if collision and is_raised else 0.025
	if not is_raised:
		midpoint.y = -0.032
	var road := _box("RoadSegment", midpoint, Vector3(width, thickness, length + 0.7), color, collision and is_raised)
	road.rotation.y = atan2(b.x - a.x, b.z - a.z)
	if is_raised:
		road.rotation.x = -atan2(b.y - a.y, maxf(length, 0.01))
	return road

func _traffic_lights(pos: Vector3) -> void:
	_box("TrafficPole", pos + Vector3(0, 2.6, 0), Vector3(0.18, 5.2, 0.18), Color("#29343d"), false)
	_box("TrafficArm", pos + Vector3(-2.0, 5.0, 0), Vector3(4.0, 0.16, 0.16), Color("#29343d"), false)
	var housing := _box("TrafficSignal", pos + Vector3(-3.75, 4.55, 0), Vector3(0.7, 1.55, 0.6), Color("#182129"), false)
	for i in range(3):
		var light := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.18
		sphere.height = 0.36
		light.mesh = sphere
		light.position = Vector3(0, 0.45 - i * 0.45, -0.32)
		var material := StandardMaterial3D.new()
		material.albedo_color = [Color("#ef5148"), Color("#e8bc39"), Color("#42cc72")][i]
		material.emission_enabled = true
		material.emission = material.albedo_color
		material.emission_energy_multiplier = 1.4 if i == 2 else 0.25
		light.material_override = material
		housing.add_child(light)

func _rooftop_detail(pos: Vector3, footprint: Vector3) -> void:
	_box("RoofTrim", pos + Vector3(0, 0.45, 0), Vector3(footprint.x + 0.5, 0.8, footprint.z + 0.5), Color("#6d7a82"), false)
	_box("RoofPlant", pos + Vector3(0, 1.2, 0), Vector3(footprint.x * 0.34, 1.4, footprint.z * 0.32), Color("#9ca8ad"), false)
	for side in [-1.0, 1.0]:
		_box("Antenna", pos + Vector3(side * footprint.x * 0.28, 3.0, 0), Vector3(0.12, 5.0, 0.12), Color("#49555c"), false)

func _house(pos: Vector3, color: Color) -> void:
	_box("House", pos + Vector3(0, 2.25, 0), Vector3(10.5, 4.5, 12.5), color, true)
	_add_building_outline(pos + Vector3(0, 2.25, 0), Vector3(10.5, 4.5, 12.5), color.darkened(0.52))
	_box("HouseUpper", pos + Vector3(0, 3.45, -0.03), Vector3(10.1, 1.85, 12.15), color.lightened(0.18), false)
	_box("HouseFloorBand", pos + Vector3(0, 2.45, -6.34), Vector3(10.7, 0.25, 0.2), Color("#f5f0e8"), false)
	var roof_color := Color("#744d42")
	var left_roof := _box("Roof", pos + Vector3(-2.7, 5.25, 0), Vector3(6.6, 0.65, 13.2), roof_color, false)
	left_roof.rotation.z = 0.48
	var right_roof := _box("Roof", pos + Vector3(2.7, 5.25, 0), Vector3(6.6, 0.65, 13.2), roof_color, false)
	right_roof.rotation.z = -0.48
	var fascia := roof_color.darkened(0.5)
	_box("RoofRidge", pos + Vector3(0, 6.52, 0), Vector3(0.34, 0.34, 13.5), fascia, false)
	_box("RoofFascia", pos + Vector3(-5.45, 4.03, 0), Vector3(0.3, 0.3, 13.5), fascia, false)
	_box("RoofFascia", pos + Vector3(5.45, 4.03, 0), Vector3(0.3, 0.3, 13.5), fascia, false)
	_box("Door", pos + Vector3(0, 1.25, -6.3), Vector3(1.7, 2.5, 0.16), Color("#533a32"), false)
	for x in [-3.1, 3.1]:
		_box("HouseWindow", pos + Vector3(x, 2.5, -6.4), Vector3(2.0, 1.7, 0.12), Color("#8ed5e9"), false)
		_box("WindowTrimTop", pos + Vector3(x, 3.38, -6.48), Vector3(2.25, 0.18, 0.16), Color("#f4f0e9"), false)
		_box("WindowTrimSide", pos + Vector3(x - 1.08, 2.5, -6.48), Vector3(0.18, 1.95, 0.16), Color("#f4f0e9"), false)
		_box("WindowTrimSide", pos + Vector3(x + 1.08, 2.5, -6.48), Vector3(0.18, 1.95, 0.16), Color("#f4f0e9"), false)
	_box("PorchCanopy", pos + Vector3(0, 2.8, -7.1), Vector3(4.2, 0.35, 2.2), roof_color, false)
	_box("Chimney", pos + Vector3(3.1, 6.2, 2.0), Vector3(1.2, 3.2, 1.2), Color("#8c5745"), false)
	# Trimmed front garden, matching the orderly suburban reference.
	_box("Hedge", pos + Vector3(-4.7, 0.65, -8.2), Vector3(5.4, 1.3, 1.0), Color("#27884c"), false)
	_box("Hedge", pos + Vector3(4.7, 0.65, -8.2), Vector3(5.4, 1.3, 1.0), Color("#27884c"), false)
	_tree(pos + Vector3(7.5, 0, 3.5))

func _mountain(pos: Vector3, height: float) -> void:
	var mountain := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = height * 0.85
	cone.height = height
	mountain.mesh = cone
	mountain.position = pos + Vector3(0, height * 0.5 - 0.3, 0)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#587b55").darkened(fmod(height, 12.0) * 0.012)
	material.roughness = 0.94
	mountain.material_override = material
	add_child(mountain)
	if height > 48.0:
		var cap := MeshInstance3D.new()
		var cap_cone := CylinderMesh.new()
		cap_cone.top_radius = 0.0
		cap_cone.bottom_radius = height * 0.22
		cap_cone.height = height * 0.26
		cap.mesh = cap_cone
		cap.position = pos + Vector3(0, height * 0.87, 0)
		var snow := StandardMaterial3D.new()
		snow.albedo_color = Color("#e8eeea")
		cap.material_override = snow
		add_child(cap)

func _road(pos: Vector3, size: Vector3) -> void:
	# Ground-level roads share the large terrain collider. Their meshes sit only
	# a few millimetres above it, so vehicles can cross every edge smoothly.
	var road_pos := Vector3(pos.x, -0.034, pos.z)
	var road_size := Vector3(size.x, 0.025, size.z)
	_box("Road", road_pos, road_size, Color("#343b43"), false)
	if size.x > size.z:
		_box("Sidewalk", Vector3(pos.x, -0.022, pos.z + size.z * 0.57), Vector3(size.x, 0.045, 2.2), Color("#b8bec3"), false)
		_box("Sidewalk", Vector3(pos.x, -0.022, pos.z - size.z * 0.57), Vector3(size.x, 0.045, 2.2), Color("#b8bec3"), false)
	else:
		_box("Sidewalk", Vector3(pos.x + size.x * 0.57, -0.022, pos.z), Vector3(2.2, 0.045, size.z), Color("#b8bec3"), false)
		_box("Sidewalk", Vector3(pos.x - size.x * 0.57, -0.022, pos.z), Vector3(2.2, 0.045, size.z), Color("#b8bec3"), false)

func _building(pos: Vector3, size: Vector3, color: Color) -> void:
	# Every building shell uses the same Kenney palette and modeling language.
	# Non-uniform scaling preserves each gameplay lot's footprint without mixing styles.
	var model_path := "res://assets/city/kenney/building-e.glb"
	var source_size := Vector3(1.64, 0.893, 1.008)
	if size.y > 22.0:
		model_path = "res://assets/city/kenney/building-n.glb"
		source_size = Vector3(2.32, 2.48, 1.82)
	elif size.x / maxf(size.z, 0.1) > 1.45:
		model_path = "res://assets/city/kenney/building-k.glb"
		source_size = Vector3(2.0836, 1.47, 0.942)
	elif size.y > 14.0:
		model_path = "res://assets/city/kenney/building-i.glb"
		source_size = Vector3(1.24, 1.68, 1.302)
	var scale_value := Vector3(size.x / source_size.x, size.y / source_size.y, size.z / source_size.z)
	var bottom_position := Vector3(pos.x, pos.y - size.y * 0.5, pos.z)
	_spawn_city_model_scaled(model_path, bottom_position, scale_value, 0.0, size)

func _add_building_outline(pos: Vector3, size: Vector3, outline: Color) -> void:
	var edge := 0.28
	var half_x := size.x * 0.5
	var half_z := size.z * 0.5
	# Four corner posts define the silhouette from every viewing direction.
	for x_side in [-1.0, 1.0]:
		for z_side in [-1.0, 1.0]:
			_box(
				"CornerTrim",
				Vector3(pos.x + x_side * (half_x + edge * 0.25), pos.y, pos.z + z_side * (half_z + edge * 0.25)),
				Vector3(edge, size.y + edge, edge),
				outline,
				false
			)
	# Continuous roofline and foundation bands outline all four façades.
	var roof_y := pos.y + size.y * 0.5 + edge * 0.15
	var base_y := pos.y - size.y * 0.5 + 0.32
	for z_side in [-1.0, 1.0]:
		_box("RoofEdge", Vector3(pos.x, roof_y, pos.z + z_side * (half_z + edge * 0.25)), Vector3(size.x + edge, edge, edge), outline, false)
		_box("BaseEdge", Vector3(pos.x, base_y, pos.z + z_side * (half_z + edge * 0.25)), Vector3(size.x + edge, 0.56, edge), outline, false)
	for x_side in [-1.0, 1.0]:
		_box("RoofEdge", Vector3(pos.x + x_side * (half_x + edge * 0.25), roof_y, pos.z), Vector3(edge, edge, size.z + edge), outline, false)
		_box("BaseEdge", Vector3(pos.x + x_side * (half_x + edge * 0.25), base_y, pos.z), Vector3(edge, 0.56, size.z + edge), outline, false)

func _tree(pos: Vector3) -> void:
	_box("Trunk", pos + Vector3(0, 1.3, 0), Vector3(0.38, 2.6, 0.38), Color("#79583b"), false)
	var crown := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 7
	sphere.rings = 4
	crown.mesh = sphere
	crown.position = pos + Vector3(0, 3.4, 0)
	crown.scale = Vector3(1.65, 1.9, 1.65)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#3d7f47")
	crown.material_override = mat
	add_child(crown)

func _box(node_name: String, pos: Vector3, size: Vector3, color: Color, collision: bool) -> Node3D:
	var root := StaticBody3D.new() if collision else Node3D.new()
	root.name = node_name
	root.position = pos
	add_child(root)
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.76
	mesh_instance.material_override = mat
	root.add_child(mesh_instance)
	if collision:
		root.collision_layer = 1
		root.collision_mask = 0
		var collider := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		collider.shape = shape
		root.add_child(collider)
	return root

func _sign(pos: Vector3, text: String, color: Color) -> Label3D:
	var label := Label3D.new()
	label.position = pos
	label.text = text
	label.font_size = 42
	label.outline_size = 8
	label.modulate = color
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	add_child(label)
	return label

func _terminal(pos: Vector3, kind: String, title: String, color: Color) -> Node3D:
	var terminal := Node3D.new()
	terminal.position = pos
	terminal.set_meta("kind", kind)
	terminal.set_meta("title", title)
	terminal.add_to_group("interactable")
	add_child(terminal)
	interactables.append(terminal)
	var base := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.75
	cylinder.bottom_radius = 0.75
	cylinder.height = 0.18
	base.mesh = cylinder
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 1.6
	base.material_override = mat
	terminal.add_child(base)
	var marker := Label3D.new()
	marker.text = "◆\n" + title
	marker.position.y = 2.1
	marker.font_size = 30
	marker.outline_size = 7
	marker.modulate = color
	marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	marker.no_depth_test = true
	terminal.add_child(marker)
	return terminal

func _spawn_player() -> void:
	player = PlayerScript.new()
	player.position = Vector3(86, 0.1, 52)
	add_child(player)

func _spawn_starter_car() -> void:
	starter_vehicle = VehicleScript.new()
	starter_vehicle.setup(self, brand_color, "NOVA C1", 1)
	starter_vehicle.position = Vector3(96, 0.1, 52)
	starter_vehicle.rotation.y = PI
	add_child(starter_vehicle)

func _build_ui() -> void:
	ui = CanvasLayer.new()
	add_child(ui)
	hud = Control.new()
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(hud)
	# Top bar
	var top := PanelContainer.new()
	top.add_theme_stylebox_override("panel", style_panel)
	top.position = Vector2(22, 20)
	top.size = Vector2(520, 70)
	hud.add_child(top)
	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 24)
	top.add_child(top_row)
	var brand := Label.new()
	brand.text = "CCE  /  NOVA MOTORS"
	brand.add_theme_font_size_override("font_size", 20)
	brand.add_theme_color_override("font_color", Color("#7ee3ff"))
	top_row.add_child(brand)
	money_label = Label.new()
	money_label.add_theme_font_size_override("font_size", 19)
	top_row.add_child(money_label)
	rep_label = Label.new()
	rep_label.add_theme_font_size_override("font_size", 17)
	top_row.add_child(rep_label)
	# Objective card
	var objective_panel := PanelContainer.new()
	objective_panel.add_theme_stylebox_override("panel", style_panel)
	objective_panel.position = Vector2(22, 105)
	objective_panel.size = Vector2(420, 92)
	hud.add_child(objective_panel)
	var objective_box := VBoxContainer.new()
	objective_panel.add_child(objective_box)
	var objective_head := Label.new()
	objective_head.text = "CURRENT CONTRACT"
	objective_head.add_theme_font_size_override("font_size", 12)
	objective_head.add_theme_color_override("font_color", Color("#64d3ff"))
	objective_box.add_child(objective_head)
	objective_label = Label.new()
	objective_label.add_theme_font_size_override("font_size", 17)
	objective_box.add_child(objective_label)
	# Interaction prompt
	action_label = Label.new()
	action_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	action_label.position = Vector2(-240, -105)
	action_label.size = Vector2(480, 56)
	action_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	action_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	action_label.add_theme_font_size_override("font_size", 18)
	action_label.add_theme_color_override("font_color", Color.WHITE)
	action_label.visible = false
	var action_bg := StyleBoxFlat.new()
	action_bg.bg_color = Color(0.02, 0.05, 0.08, 0.88)
	action_bg.set_corner_radius_all(9)
	action_label.add_theme_stylebox_override("normal", action_bg)
	hud.add_child(action_label)
	# Small center reticle for walking, driving and lining up interactions.
	var reticle := Panel.new()
	reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	reticle.set_anchors_preset(Control.PRESET_CENTER)
	reticle.position = Vector2(-3, -3)
	reticle.size = Vector2(6, 6)
	var reticle_style := StyleBoxFlat.new()
	reticle_style.bg_color = Color(1, 1, 1, 0.96)
	reticle_style.border_color = Color(0, 0, 0, 0.45)
	reticle_style.set_border_width_all(1)
	reticle_style.set_corner_radius_all(3)
	reticle.add_theme_stylebox_override("panel", reticle_style)
	hud.add_child(reticle)
	# Controls
	var controls := Label.new()
	controls.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	controls.position = Vector2(24, -64)
	controls.text = "WASD  MOVE / DRIVE     SHIFT  SPRINT     SPACE  JUMP / HANDBRAKE     E  INTERACT"
	controls.add_theme_font_size_override("font_size", 13)
	controls.add_theme_color_override("font_color", Color(0.86, 0.92, 0.98, 0.75))
	hud.add_child(controls)
	# Speedometer
	speed_panel = PanelContainer.new()
	speed_panel.add_theme_stylebox_override("panel", style_panel)
	speed_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	speed_panel.position = Vector2(-238, -168)
	speed_panel.size = Vector2(210, 130)
	speed_panel.visible = false
	hud.add_child(speed_panel)
	speed_label = Label.new()
	speed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	speed_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	speed_label.add_theme_font_size_override("font_size", 22)
	speed_panel.add_child(speed_label)
	# Toast
	toast = Label.new()
	toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	toast.position = Vector2(-250, 26)
	toast.size = Vector2(500, 55)
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	toast.add_theme_font_size_override("font_size", 17)
	toast.add_theme_stylebox_override("normal", style_panel)
	toast.modulate.a = 0.0
	hud.add_child(toast)
	online_status_label = Label.new()
	online_status_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	online_status_label.position = Vector2(-320, 24)
	online_status_label.size = Vector2(294, 40)
	online_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	online_status_label.add_theme_font_size_override("font_size", 15)
	online_status_label.add_theme_color_override("font_color", Color("#8fe7ff"))
	online_status_label.text = "ONLINE  •  SIGN IN REQUIRED"
	hud.add_child(online_status_label)
	online_roster_panel = PanelContainer.new()
	online_roster_panel.add_theme_stylebox_override("panel", style_panel)
	online_roster_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	online_roster_panel.position = Vector2(-320, 70)
	online_roster_panel.size = Vector2(294, 90)
	online_roster_panel.visible = false
	hud.add_child(online_roster_panel)
	online_roster_label = Label.new()
	online_roster_label.add_theme_font_size_override("font_size", 14)
	online_roster_label.add_theme_color_override("font_color", Color("#d8efff"))
	online_roster_panel.add_child(online_roster_label)
	var account_button := _ui_button("ACCOUNT")
	account_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	account_button.position = Vector2(-148, 170)
	account_button.size = Vector2(122, 42)
	account_button.pressed.connect(_open_account_settings)
	hud.add_child(account_button)
	# Modal shell
	modal = PanelContainer.new()
	modal.add_theme_stylebox_override("panel", style_panel)
	modal.set_anchors_preset(Control.PRESET_CENTER)
	modal.position = Vector2(-310, -270)
	modal.size = Vector2(620, 540)
	modal.visible = false
	ui.add_child(modal)
	modal_body = VBoxContainer.new()
	modal_body.add_theme_constant_override("separation", 12)
	modal.add_child(modal_body)
	_refresh_hud()

func _show_main_menu() -> void:
	if auth_token.is_empty():
		_show_auth_screen(true)
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_clear_startup_screen()
	company_setup = _startup_backdrop()
	var card := _startup_card(Vector2(600, 500))
	company_setup.add_child(card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	card.add_child(box)
	_add_startup_heading(box, "CAR COMPANY EMPIRE", "BUILD. DRIVE. DOMINATE.")
	var sub := Label.new()
	sub.text = "SIGNED IN AS  %s  /  %s\nBuild your company alongside real players." % [player_username, company_name]
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 17)
	sub.add_theme_color_override("font_color", Color("#aebdca"))
	box.add_child(sub)
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 22
	box.add_child(spacer)
	var play := _ui_button("PLAY")
	play.custom_minimum_size.y = 66
	play.pressed.connect(_begin_online_play)
	box.add_child(play)
	var settings := _ui_button("SETTINGS")
	settings.custom_minimum_size.y = 54
	settings.pressed.connect(_show_settings_screen)
	box.add_child(settings)
	var online_only := Label.new()
	online_only.text = "ONLINE ACCOUNT REQUIRED  •  PROGRESS SAVES AUTOMATICALLY"
	online_only.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	online_only.add_theme_font_size_override("font_size", 12)
	online_only.add_theme_color_override("font_color", Color("#63d5ff"))
	box.add_child(online_only)

func _show_settings_screen() -> void:
	_clear_startup_screen()
	company_setup = _startup_backdrop()
	var card := _startup_card(Vector2(600, 520))
	company_setup.add_child(card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	card.add_child(box)
	_add_startup_heading(box, "SETTINGS", "GAME & CONTROLS")
	var controls := Label.new()
	controls.text = "WASD  —  MOVE / DRIVE\nSHIFT  —  SPRINT\nSPACE  —  JUMP / HANDBRAKE\nE  —  INTERACT\nESC  —  RELEASE MOUSE"
	controls.add_theme_font_size_override("font_size", 18)
	controls.add_theme_color_override("font_color", Color("#d7e6f2"))
	box.add_child(controls)
	var fullscreen := _ui_button("TOGGLE FULLSCREEN")
	fullscreen.custom_minimum_size.y = 52
	fullscreen.pressed.connect(_toggle_fullscreen)
	box.add_child(fullscreen)
	var back := _ui_button("BACK")
	back.custom_minimum_size.y = 52
	back.pressed.connect(_show_main_menu)
	box.add_child(back)

func _show_auth_screen(sign_in: bool) -> void:
	_clear_startup_screen()
	company_setup = _startup_backdrop()
	var card_size := Vector2(680, 575 if sign_in else 685)
	var card := _startup_card(card_size)
	company_setup.add_child(card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 11)
	card.add_child(box)
	_add_startup_heading(box, "CAR COMPANY EMPIRE", "SIGN IN" if sign_in else "CREATE ACCOUNT")
	var mode_row := HBoxContainer.new()
	mode_row.add_theme_constant_override("separation", 10)
	box.add_child(mode_row)
	var sign_in_tab := _ui_button("SIGN IN")
	sign_in_tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sign_in_tab.pressed.connect(_show_auth_screen.bind(true))
	mode_row.add_child(sign_in_tab)
	var sign_up_tab := _ui_button("SIGN UP")
	sign_up_tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sign_up_tab.pressed.connect(_show_auth_screen.bind(false))
	mode_row.add_child(sign_up_tab)
	var username_input := _auth_input(box, "USERNAME", "Your player username", false, 18)
	var password_input := _auth_input(box, "PASSWORD", "At least 6 characters", true, 72)
	var show_password := CheckButton.new()
	show_password.text = "SHOW PASSWORD"
	show_password.add_theme_font_size_override("font_size", 13)
	show_password.add_theme_color_override("font_color", Color("#b8ccdc"))
	show_password.toggled.connect(_toggle_password_visibility.bind(password_input))
	box.add_child(show_password)
	var company_input: LineEdit
	if not sign_in:
		company_input = _auth_input(box, "COMPANY NAME", "Your automotive company", false, 32)
		var color_label := Label.new()
		color_label.text = "COMPANY COLOR"
		color_label.add_theme_font_size_override("font_size", 12)
		box.add_child(color_label)
		var colors := HBoxContainer.new()
		colors.add_theme_constant_override("separation", 10)
		box.add_child(colors)
		var palette := [Color("#ff6333"), Color("#1677ff"), Color("#24c78a"), Color("#a95cff"), Color("#f2c94c")]
		for index in range(palette.size()):
			var color: Color = palette[index]
			var color_button := Button.new()
			color_button.custom_minimum_size = Vector2(72, 44)
			color_button.focus_mode = Control.FOCUS_NONE
			color_button.add_theme_font_size_override("font_size", 22)
			color_button.add_theme_color_override("font_color", Color.WHITE)
			var color_style := StyleBoxFlat.new()
			color_style.bg_color = color
			color_style.set_corner_radius_all(8)
			color_button.add_theme_stylebox_override("normal", color_style)
			color_button.add_theme_stylebox_override("hover", color_style)
			color_button.add_theme_stylebox_override("pressed", color_style)
			colors.add_child(color_button)
			color_button.pressed.connect(_select_brand_color.bind(color, color_button, colors))
			if index == 0:
				_select_brand_color(color, color_button, colors)
	var error_label := Label.new()
	error_label.name = "AuthError"
	error_label.custom_minimum_size.y = 40
	error_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	error_label.add_theme_font_size_override("font_size", 14)
	error_label.add_theme_color_override("font_color", Color("#ff8d8d"))
	box.add_child(error_label)
	var submit := _ui_button("SIGN IN" if sign_in else "CREATE ACCOUNT")
	submit.custom_minimum_size.y = 58
	if sign_in:
		submit.pressed.connect(_submit_sign_in.bind(username_input, password_input, submit, error_label))
	else:
		submit.pressed.connect(_submit_sign_up.bind(username_input, password_input, company_input, submit, error_label))
	box.add_child(submit)

func _startup_backdrop() -> ColorRect:
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.008, 0.02, 0.04, 0.96)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.add_child(backdrop)
	return backdrop

func _startup_card(card_size: Vector2) -> PanelContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", style_panel)
	card.set_anchors_preset(Control.PRESET_CENTER)
	card.position = -card_size * 0.5
	card.size = card_size
	return card

func _add_startup_heading(box: VBoxContainer, kicker_text: String, title_text: String) -> void:
	var kicker := Label.new()
	kicker.text = kicker_text
	kicker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	kicker.add_theme_font_size_override("font_size", 14)
	kicker.add_theme_color_override("font_color", Color("#63d5ff"))
	box.add_child(kicker)
	var title := Label.new()
	title.text = title_text
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 36)
	box.add_child(title)

func _auth_input(box: VBoxContainer, label_text: String, placeholder: String, secret: bool, limit: int) -> LineEdit:
	var label := Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", 12)
	box.add_child(label)
	var input := LineEdit.new()
	input.placeholder_text = placeholder
	input.max_length = limit
	input.secret = secret
	input.add_theme_font_size_override("font_size", 19)
	input.custom_minimum_size.y = 44
	box.add_child(input)
	return input

func _toggle_password_visibility(visible_password: bool, password_input: LineEdit) -> void:
	password_input.secret = not visible_password

func _submit_sign_in(username_input: LineEdit, password_input: LineEdit, button: Button, error_label: Label) -> void:
	_submit_auth("/signin", {
		"username": username_input.text.strip_edges(),
		"password": password_input.text,
	}, button, error_label)

func _submit_sign_up(username_input: LineEdit, password_input: LineEdit, company_input: LineEdit, button: Button, error_label: Label) -> void:
	_submit_auth("/signup", {
		"username": username_input.text.strip_edges(),
		"password": password_input.text,
		"company": company_input.text.strip_edges(),
		"color": brand_color.to_html(false),
	}, button, error_label)

func _submit_auth(endpoint: String, body: Dictionary, button: Button, error_label: Label) -> void:
	if auth_request.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		return
	button.disabled = true
	button.text = "CONTACTING SERVER…"
	error_label.text = ""
	auth_request.set_meta("button", button)
	auth_request.set_meta("error_label", error_label)
	var headers := PackedStringArray(["Content-Type: application/json"])
	var error := auth_request.request(_account_api_url() + endpoint, headers, HTTPClient.METHOD_POST, JSON.stringify(body))
	if error != OK:
		button.disabled = false
		button.text = "TRY AGAIN"
		error_label.text = "Could not contact the account server."

func _on_auth_request_completed(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var button := auth_request.get_meta("button") as Button
	var error_label := auth_request.get_meta("error_label") as Label
	var parsed = JSON.parse_string(body.get_string_from_utf8())
	if response_code < 200 or response_code >= 300 or not parsed is Dictionary:
		if is_instance_valid(button):
			button.disabled = false
			button.text = "TRY AGAIN"
		if is_instance_valid(error_label):
			error_label.text = str(parsed.get("error", "Account server unavailable.")) if parsed is Dictionary else "Account server unavailable."
		return
	auth_token = str(parsed.get("token", ""))
	var account = parsed.get("account", {})
	if auth_token.is_empty() or not account is Dictionary:
		if is_instance_valid(error_label):
			error_label.text = "The account server returned an invalid response."
		return
	_apply_account(account)
	_show_main_menu()

func _begin_online_play() -> void:
	_show_loading_screen("JOINING ONLINE WORLD…")
	_connect_online_world()

func _account_api_url() -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--account-url="):
			return argument.trim_prefix("--account-url=")
	return ACCOUNT_API_BASE_URL

func _connect_online_world() -> void:
	online_socket = WebSocketPeer.new()
	var error := online_socket.connect_to_url(_online_server_url())
	if error != OK:
		_show_connection_failure("The online world is unavailable (error %d)." % error)
		return
	online_mode = "connecting"
	online_connected = false
	online_peer_id = 0
	if loading_label:
		loading_label.text = "JOINING ONLINE WORLD…"

func _show_loading_screen(message: String) -> void:
	_clear_startup_screen()
	loading_screen = _startup_backdrop()
	company_setup = loading_screen
	var card := _startup_card(Vector2(580, 300))
	loading_screen.add_child(card)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 18)
	card.add_child(box)
	var title := Label.new()
	title.text = "CAR COMPANY EMPIRE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color("#63d5ff"))
	box.add_child(title)
	loading_label = Label.new()
	loading_label.text = message
	loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	loading_label.add_theme_font_size_override("font_size", 28)
	box.add_child(loading_label)
	var hint := Label.new()
	hint.text = "Waking the server and restoring your company.\nThis can take about a minute."
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 15)
	hint.add_theme_color_override("font_color", Color("#aebdca"))
	box.add_child(hint)

func _show_connection_failure(message: String) -> void:
	online_mode = "menu"
	_clear_startup_screen()
	company_setup = _startup_backdrop()
	var card := _startup_card(Vector2(600, 400))
	company_setup.add_child(card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 20)
	card.add_child(box)
	_add_startup_heading(box, "CONNECTION FAILED", "ONLINE REQUIRED")
	var error := Label.new()
	error.text = message + "\nThere is no offline mode."
	error.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	error.add_theme_font_size_override("font_size", 17)
	error.add_theme_color_override("font_color", Color("#ff9a9a"))
	box.add_child(error)
	var retry := _ui_button("RETRY")
	retry.pressed.connect(func():
		_show_loading_screen("RECONNECTING…")
		_connect_online_world()
	)
	box.add_child(retry)
	var back := _ui_button("BACK TO SIGN IN")
	back.text = "BACK TO MAIN MENU"
	back.pressed.connect(_show_main_menu)
	box.add_child(back)

func _finish_online_launch() -> void:
	game_started = true
	hud.visible = true
	_clear_startup_screen()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	player.set_active(true)
	starter_vehicle.set_body_color(brand_color)
	for plot in factory_plots:
		if bool(plot.get_meta("is_local_owner", false)):
			plot.set_meta("owner_company", company_name)
	_refresh_hud()
	_show_toast("Connected. Your company progress is saved online.")

func _clear_startup_screen() -> void:
	if company_setup and is_instance_valid(company_setup):
		company_setup.queue_free()
	company_setup = null
	loading_screen = null
	loading_label = null

func _toggle_fullscreen() -> void:
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

func _apply_account(account: Dictionary) -> void:
	player_username = str(account.get("username", "DRIVER")).left(18)
	company_name = str(account.get("company", "NOVA MOTORS")).to_upper().left(32)
	var color_text := str(account.get("color", "ff6333"))
	brand_color = Color("#" + color_text.trim_prefix("#"))
	var progress = account.get("progress", {})
	if not progress is Dictionary:
		progress = {}
	money = int(progress.get("money", 25000))
	reputation = int(progress.get("reputation", 0))
	company_level = int(progress.get("company_level", 1))
	research = int(progress.get("research", 0))
	total_built = int(progress.get("total_built", 0))
	total_sales = int(progress.get("total_sales", 0))
	objective_stage = int(progress.get("objective_stage", 0))
	var loaded_inventory = progress.get("inventory", {})
	if loaded_inventory is Dictionary:
		for part in inventory.keys():
			inventory[part] = int(loaded_inventory.get(part, inventory[part]))
	var loaded_position = progress.get("player_position", {})
	if loaded_position is Dictionary:
		player.position = Vector3(
			float(loaded_position.get("x", 86.0)),
			float(loaded_position.get("y", 0.1)),
			float(loaded_position.get("z", 52.0))
		)
	for vehicle in manufactured_vehicles:
		if is_instance_valid(vehicle):
			vehicle.queue_free()
	manufactured_vehicles.clear()
	var cars = progress.get("cars", [])
	if cars is Array:
		for car_data in cars:
			if car_data is Dictionary:
				_spawn_saved_vehicle(car_data)
	manufactured = manufactured_vehicles.size()
	starter_vehicle.brand_name = company_name.left(8) + " C1"
	starter_vehicle.set_body_color(brand_color)
	progress_dirty = false
	autosave_accumulator = 0.0

func _spawn_saved_vehicle(car_data: Dictionary) -> void:
	var car := VehicleScript.new()
	var color_text := str(car_data.get("color", brand_color.to_html(false)))
	var car_color := Color("#" + color_text.trim_prefix("#"))
	var model_name := str(car_data.get("name", company_name.left(4) + " MODEL")).left(24)
	var quality := maxi(1, int(car_data.get("quality", 1)))
	car.setup(self, car_color, model_name, quality)
	var parking_index := manufactured_vehicles.size()
	car.position = _factory_parking_position(parking_index)
	car.rotation.y = PI
	add_child(car)
	manufactured_vehicles.append(car)

func _progress_payload() -> Dictionary:
	var cars: Array[Dictionary] = []
	for vehicle in manufactured_vehicles:
		if is_instance_valid(vehicle):
			cars.append({
				"name": vehicle.brand_name,
				"quality": vehicle.quality,
				"color": vehicle.body_color.to_html(false),
			})
	var saved_position := player.global_position
	if current_vehicle:
		saved_position = current_vehicle.global_position
	return {
		"money": money,
		"reputation": reputation,
		"company_level": company_level,
		"research": research,
		"inventory": inventory.duplicate(true),
		"cars": cars,
		"total_built": total_built,
		"total_sales": total_sales,
		"objective_stage": objective_stage,
		"player_position": {
			"x": saved_position.x,
			"y": saved_position.y,
			"z": saved_position.z,
		},
	}

func _save_progress() -> void:
	if auth_token.is_empty() or save_in_flight or not game_started:
		return
	save_in_flight = true
	progress_dirty = false
	autosave_accumulator = 0.0
	var headers := PackedStringArray([
		"Content-Type: application/json",
		"Authorization: Bearer " + auth_token,
	])
	var error := save_request.request(
		_account_api_url() + "/progress",
		headers,
		HTTPClient.METHOD_PUT,
		JSON.stringify({"progress": _progress_payload()})
	)
	if error != OK:
		save_in_flight = false
		progress_dirty = true

func _on_save_request_completed(_result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	save_in_flight = false
	if response_code < 200 or response_code >= 300:
		progress_dirty = true

func _open_account_settings() -> void:
	panel_open = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	player.enabled = false
	modal.visible = true
	for child in modal_body.get_children():
		child.queue_free()
	var title := Label.new()
	title.text = "ACCOUNT"
	title.add_theme_font_size_override("font_size", 29)
	modal_body.add_child(title)
	var identity := Label.new()
	identity.text = "%s\n%s\n\nProgress saves automatically to your online account." % [player_username, company_name]
	identity.add_theme_font_size_override("font_size", 17)
	identity.add_theme_color_override("font_color", Color("#d8e6f2"))
	modal_body.add_child(identity)
	var delete_button := _ui_button("DELETE ACCOUNT")
	delete_button.add_theme_color_override("font_color", Color("#ffb0b0"))
	delete_button.pressed.connect(_account_delete_pressed.bind(delete_button))
	modal_body.add_child(delete_button)
	var close := _ui_button("CLOSE")
	close.pressed.connect(_close_modal)
	modal_body.add_child(close)

func _account_delete_pressed(button: Button) -> void:
	if bool(button.get_meta("delete_armed", false)):
		_delete_account(button)
		return
	button.set_meta("delete_armed", true)
	button.text = "CONFIRM: DELETE ACCOUNT PERMANENTLY"

func _delete_account(button: Button) -> void:
	if delete_request.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		return
	button.disabled = true
	button.text = "DELETING ACCOUNT…"
	var headers := PackedStringArray(["Authorization: Bearer " + auth_token])
	var error := delete_request.request(
		_account_api_url() + "/account",
		headers,
		HTTPClient.METHOD_DELETE
	)
	if error != OK:
		button.disabled = false
		button.text = "DELETE FAILED — TRY AGAIN"

func _on_delete_request_completed(_result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	if response_code < 200 or response_code >= 300:
		_show_toast("Account deletion failed. Try again.")
		return
	game_started = false
	auth_token = ""
	modal.visible = false
	panel_open = false
	hud.visible = false
	player.set_active(false)
	if online_socket:
		online_socket.close()
	_clear_online_session()
	_show_auth_screen(true)

func _online_server_url() -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--online-url="):
			return argument.trim_prefix("--online-url=")
	return ONLINE_SERVER_URL

func _select_brand_color(color: Color, selected_button: Button, group: HBoxContainer) -> void:
	brand_color = color
	for child in group.get_children():
		if child is Button:
			child.text = ""
			var style := child.get_theme_stylebox("normal") as StyleBoxFlat
			if style:
				style.set_border_width_all(0)
	selected_button.text = "✓"
	var selected_style := selected_button.get_theme_stylebox("normal") as StyleBoxFlat
	if selected_style:
		selected_style.border_color = Color.WHITE
		selected_style.set_border_width_all(3)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var setup_active := company_setup and is_instance_valid(company_setup)
		if not setup_active and not panel_open and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _process(delta: float) -> void:
	time_of_day += delta * 0.025
	sun.rotation_degrees.x = -48.0 + sin(time_of_day * 0.25) * 10.0
	_update_online_multiplayer(delta)
	if game_started:
		autosave_accumulator += delta
		if autosave_accumulator >= AUTOSAVE_INTERVAL or (progress_dirty and autosave_accumulator >= 2.0):
			_save_progress()
	if company_setup and is_instance_valid(company_setup):
		return
	_update_nearest()
	if not panel_open and Input.is_action_just_pressed("interact"):
		_interact()

func _update_nearest() -> void:
	nearest = null
	var best := 5.0
	var origin := current_vehicle.global_position if current_vehicle else player.global_position
	if not current_vehicle:
		for vehicle in get_tree().get_nodes_in_group("vehicles"):
			if bool(vehicle.get_meta("online_remote", false)):
				continue
			var d: float = origin.distance_to(vehicle.global_position)
			if d < best:
				best = d
				nearest = vehicle
	for item in interactables:
		var distance := origin.distance_to(item.global_position)
		if distance < best:
			best = distance
			nearest = item
	action_label.visible = nearest != null or current_vehicle != null
	if current_vehicle:
		action_label.text = "[ E ]  EXIT VEHICLE"
	elif nearest is EmpireVehicle:
		action_label.text = "[ E ]  DRIVE " + nearest.brand_name
	elif nearest:
		action_label.text = "[ E ]  " + str(nearest.get_meta("title"))

func _interact() -> void:
	if current_vehicle:
		current_vehicle.exit()
		return
	if nearest is EmpireVehicle:
		nearest.enter(player)
		if objective_stage == 0:
			objective_stage = 1
			_show_toast("Starter vehicle acquired. Visit a supplier.")
			_refresh_hud()
		return
	if nearest:
		_open_location(str(nearest.get_meta("kind")))

func _open_location(kind: String) -> void:
	panel_open = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	player.enabled = false
	modal.visible = true
	for child in modal_body.get_children():
		child.queue_free()
	var title := Label.new()
	title.add_theme_font_size_override("font_size", 29)
	modal_body.add_child(title)
	var subtitle := Label.new()
	subtitle.add_theme_font_size_override("font_size", 15)
	subtitle.add_theme_color_override("font_color", Color("#aebdcc"))
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	modal_body.add_child(subtitle)
	match kind:
		"engine_shop":
			title.text = "APEX ENGINE WORKS"
			subtitle.text = "Performance engines and transmissions. Components are delivered directly to factory storage."
			_shop_item("1.6L Inline-4 Engine", "Engine", 4200, "128 hp  •  142 kg  •  Reliability 88")
			_shop_item("6-Speed Transmission", "Transmission", 2600, "92% efficiency  •  Reliability 91")
		"chassis_shop":
			title.text = "METRO CHASSIS SUPPLY"
			subtitle.text = "Certified modular platforms and road-ready rolling assemblies."
			_shop_item("Compact Steel Chassis", "Chassis", 3500, "310 kg  •  Economy / Sport compatible")
			_shop_item("Road Wheel Set", "Wheels", 1400, "17 inch  •  Grip 76")
		"electronics_shop":
			title.text = "VOLT LABS"
			subtitle.text = "Advanced electronics unlock premium vehicle features and higher sale values."
			_shop_item("Vehicle Electronics Suite", "Electronics", 5200, "Driver assists  •  Digital cockpit")
		"factory":
			title.text = "ASSEMBLY LINE"
			subtitle.text = "Owned components act as reusable production blueprints. The $3,000 fee covers fresh materials for every car."
			_add_inventory_summary()
			var model_name_input := LineEdit.new()
			model_name_input.placeholder_text = "Enter new car model name"
			model_name_input.text = company_name.left(4) + " MODEL " + str(total_built + 1)
			model_name_input.max_length = 24
			model_name_input.add_theme_font_size_override("font_size", 18)
			modal_body.add_child(model_name_input)
			var can_build: bool = inventory["Chassis"] > 0 and inventory["Engine"] > 0 and inventory["Transmission"] > 0 and inventory["Wheels"] > 0
			var build := _ui_button("MANUFACTURE VEHICLE  •  $3,000")
			build.disabled = not can_build or money < 3000
			build.pressed.connect(_manufacture.bind(model_name_input))
			modal_body.add_child(build)
		"storage":
			title.text = "PARTS STORAGE"
			subtitle.text = "All purchased and recovered components are tracked here."
			_add_inventory_summary()
		"design":
			title.text = "DESIGN STUDIO"
			subtitle.text = "Develop improved models and license advanced technology."
			var research_button := _ui_button("RESEARCH QUALITY PACKAGE  •  $7,500")
			research_button.disabled = money < 7500
			research_button.pressed.connect(_research_upgrade)
			modal_body.add_child(research_button)
		"dealership":
			title.text = "EMPIRE AUTO GALLERY"
			subtitle.text = "Choose a specific manufactured vehicle to sell. The sold car will leave your inventory and the world."
			var sale_value := 14500 + research * 3500
			_add_vehicle_sale_list(sale_value, "SELL")
		"auction":
			title.text = "EMPIRE MOTOR AUCTION"
			subtitle.text = "Choose a specific manufactured vehicle to auction to collectors for a higher return."
			var auction_value := 18500 + research * 4000
			_add_vehicle_sale_list(auction_value, "AUCTION")
		"race":
			title.text = "R&D TEST CIRCUIT"
			subtitle.text = "Complete a manufacturer test session to earn research data and reputation."
			var test := _ui_button("RUN CERTIFICATION TEST  •  +15 REP")
			test.pressed.connect(_complete_test)
			modal_body.add_child(test)
		"airport_cargo":
			title.text = "EMPIRE INTERNATIONAL CARGO"
			subtitle.text = "Air freight provides rare electronics and lightweight components at premium prices."
			_shop_item("Imported Electronics Suite", "Electronics", 6800, "Quality 94  •  Low weight  •  Premium cockpit")
			_shop_item("Airfreight Transmission", "Transmission", 3900, "8-speed  •  Quality 88  •  Limited import")
		"dock_imports":
			title.text = "PORT EMPIRE IMPORTS"
			subtitle.text = "Container shipments offer reliable bulk components for your production line."
			_shop_item("Imported Modular Chassis", "Chassis", 4100, "SUV / Sport compatible  •  Quality 82")
			_shop_item("Touring Wheel Set", "Wheels", 1750, "18 inch  •  Grip 81  •  Durable")
		"custom_shop":
			title.text = "AZURE CUSTOMS ATELIER"
			subtitle.text = "Luxury engineering increases brand prestige and the value of every manufactured vehicle."
			var prestige := _ui_button("COMMISSION BRAND PACKAGE  •  $9,000")
			prestige.disabled = money < 9000
			prestige.pressed.connect(_prestige_upgrade)
			modal_body.add_child(prestige)
		"rival_factory":
			title.text = "RIVAL MOTORS"
			subtitle.text = "This factory plot belongs to another player company. Suppliers, the dealership and auction house are shared city services."
	var close := _ui_button("CLOSE")
	close.pressed.connect(_close_modal)
	modal_body.add_child(close)

func _add_vehicle_sale_list(base_value: int, action_text: String) -> void:
	for index in range(manufactured_vehicles.size() - 1, -1, -1):
		if not is_instance_valid(manufactured_vehicles[index]):
			manufactured_vehicles.remove_at(index)
	manufactured = manufactured_vehicles.size()
	if manufactured_vehicles.is_empty():
		var empty := Label.new()
		empty.text = "NO MANUFACTURED VEHICLES AVAILABLE\nBuild a named vehicle at your factory first."
		empty.add_theme_font_size_override("font_size", 17)
		empty.add_theme_color_override("font_color", Color("#9fb0be"))
		modal_body.add_child(empty)
		return
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 235)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	modal_body.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 9)
	scroll.add_child(list)
	for vehicle in manufactured_vehicles:
		var value := base_value + maxi(0, vehicle.quality - 1) * 1500
		var card := PanelContainer.new()
		var card_style := StyleBoxFlat.new()
		card_style.bg_color = Color(0.06, 0.11, 0.16, 0.96)
		card_style.border_color = Color(0.15, 0.3, 0.42, 0.9)
		card_style.set_border_width_all(1)
		card_style.set_corner_radius_all(8)
		card_style.content_margin_left = 12
		card_style.content_margin_right = 12
		card_style.content_margin_top = 9
		card_style.content_margin_bottom = 9
		card.add_theme_stylebox_override("panel", card_style)
		list.add_child(card)
		var row := HBoxContainer.new()
		card.add_child(row)
		var details := Label.new()
		details.text = vehicle.brand_name + "\nQuality level " + str(vehicle.quality)
		details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		details.add_theme_font_size_override("font_size", 16)
		row.add_child(details)
		var action := _ui_button(action_text + "  •  $" + _format_money(value))
		action.pressed.connect(_sell_vehicle.bind(vehicle, value))
		row.add_child(action)

func _shop_item(display_name: String, part: String, cost: int, stats: String) -> void:
	var card := PanelContainer.new()
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Color(0.07, 0.12, 0.17, 0.95)
	card_style.set_corner_radius_all(8)
	card_style.content_margin_left = 12
	card_style.content_margin_right = 12
	card_style.content_margin_top = 10
	card_style.content_margin_bottom = 10
	card.add_theme_stylebox_override("panel", card_style)
	modal_body.add_child(card)
	var row := HBoxContainer.new()
	card.add_child(row)
	var text := Label.new()
	text.text = display_name + "\n" + stats
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_font_size_override("font_size", 15)
	row.add_child(text)
	var buy := _ui_button("$" + _format_money(cost))
	buy.disabled = money < cost
	buy.pressed.connect(func(): _buy_part(part, cost, display_name))
	row.add_child(buy)

func _add_inventory_summary() -> void:
	var text := Label.new()
	text.text = "FACTORY INVENTORY\n"
	for part in inventory:
		text.text += "   %-14s  × %d\n" % [part, inventory[part]]
	text.add_theme_font_size_override("font_size", 17)
	text.add_theme_color_override("font_color", Color("#d8e6f2"))
	modal_body.add_child(text)

func _ui_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", 16)
	button.add_theme_stylebox_override("normal", style_button)
	button.add_theme_stylebox_override("hover", style_button)
	return button

func _buy_part(part: String, cost: int, display_name: String) -> void:
	if money < cost:
		return
	money -= cost
	inventory[part] += 1
	if objective_stage <= 1:
		objective_stage = 2
	_show_toast(display_name + " delivered to factory.")
	_refresh_hud()
	_close_modal()

func _manufacture(model_name_input: LineEdit) -> void:
	if money < 3000:
		return
	for part in ["Chassis", "Engine", "Transmission", "Wheels"]:
		if inventory[part] <= 0:
			return
	var model_name := model_name_input.text.strip_edges().to_upper()
	if model_name.is_empty():
		model_name = company_name.left(4) + " MODEL " + str(total_built + 1)
	money -= 3000
	total_built += 1
	var car := VehicleScript.new()
	car.setup(self, brand_color.lightened(0.045 * (total_built % 4)), model_name, research + 1)
	var parking_index := manufactured_vehicles.size()
	car.position = _factory_parking_position(parking_index)
	car.rotation.y = PI
	add_child(car)
	manufactured_vehicles.append(car)
	manufactured = manufactured_vehicles.size()
	objective_stage = 3
	reputation += 10
	_show_toast(model_name + " completed. It is ready for sale.")
	_refresh_hud()
	_close_modal()

func _research_upgrade() -> void:
	if money < 7500:
		return
	money -= 7500
	research += 1
	reputation += 20
	if research >= 2:
		company_level = 2
	_show_toast("Quality package unlocked. Vehicle value increased.")
	_refresh_hud()
	_close_modal()

func _prestige_upgrade() -> void:
	if money < 9000:
		return
	money -= 9000
	research += 1
	reputation += 30
	company_level = maxi(company_level, 2)
	_show_toast("Luxury brand package installed: +30 reputation.")
	_refresh_hud()
	_close_modal()

func _sell_vehicle(vehicle: EmpireVehicle, value: int) -> void:
	if not is_instance_valid(vehicle) or not manufactured_vehicles.has(vehicle):
		return
	var sold_name := vehicle.brand_name
	manufactured_vehicles.erase(vehicle)
	manufactured = manufactured_vehicles.size()
	if current_vehicle == vehicle:
		current_vehicle = null
	vehicle.queue_free()
	money += value
	total_sales += 1
	reputation += 35
	objective_stage = 4
	if total_sales >= 2:
		company_level = 2
	_show_toast(sold_name + " sold and removed from your inventory.")
	_refresh_hud()
	_close_modal()

func _complete_test() -> void:
	research += 1
	reputation += 15
	money += 1200
	_show_toast("Certification passed: +15 reputation, +$1,200.")
	_refresh_hud()
	_close_modal()

func _close_modal() -> void:
	modal.visible = false
	panel_open = false
	player.enabled = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _refresh_hud() -> void:
	if not money_label:
		return
	money_label.text = "$" + _format_money(money)
	rep_label.text = "LVL %d  •  %d REP" % [company_level, reputation]
	var objectives := [
		"Enter your starter car and explore the city.",
		"Visit a supplier and purchase a component.",
		"Return to your factory and manufacture a car.",
		"Sell your new vehicle at Empire Auto Gallery.",
		"Grow the company: research, race and manufacture.",
	]
	objective_label.text = objectives[clampi(objective_stage, 0, objectives.size() - 1)]
	var brand_labels := hud.get_children()
	if brand_labels.size() > 0:
		var top_panel = brand_labels[0]
		if top_panel is PanelContainer:
			var row = top_panel.get_child(0)
			if row and row.get_child_count() > 0:
				row.get_child(0).text = "CCE  /  " + company_name
	if game_started:
		progress_dirty = true

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT and game_started:
		progress_dirty = true
		_save_progress()

func _format_money(value: int) -> String:
	var text := str(value)
	var result := ""
	while text.length() > 3:
		result = "," + text.right(3) + result
		text = text.left(text.length() - 3)
	return text + result

func _show_toast(message: String) -> void:
	toast.text = message
	if toast_tween:
		toast_tween.kill()
	toast.modulate.a = 1.0
	toast_tween = create_tween()
	toast_tween.tween_interval(2.4)
	toast_tween.tween_property(toast, "modulate:a", 0.0, 0.5)

func set_driving(value: bool, vehicle: EmpireVehicle) -> void:
	current_vehicle = vehicle
	speed_panel.visible = value
	if not value:
		speed_label.text = ""

func update_vehicle_hud(kph: float, vehicle_name: String) -> void:
	speed_label.text = "%03d\nKM/H\n%s" % [int(kph), vehicle_name]

func _update_online_multiplayer(delta: float) -> void:
	if online_socket == null:
		return
	online_socket.poll()
	var ready_state := online_socket.get_ready_state()
	if ready_state == WebSocketPeer.STATE_OPEN:
		if not online_connected:
			online_connected = true
			_send_online_message({
				"type": "join",
				"token": auth_token,
			})
		while online_socket.get_available_packet_count() > 0:
			var packet := online_socket.get_packet()
			var parsed = JSON.parse_string(packet.get_string_from_utf8())
			if parsed is Dictionary:
				_handle_online_message(parsed)
	elif ready_state == WebSocketPeer.STATE_CLOSED:
		_clear_online_session()
		game_started = false
		hud.visible = false
		player.set_active(false)
		_show_connection_failure("Connection to the shared world was lost.")
		return
	else:
		return
	if online_peer_id == 0:
		return
	network_send_accumulator += delta
	if network_send_accumulator < NETWORK_SEND_INTERVAL:
		return
	network_send_accumulator = 0.0
	var position_to_send := player.global_position
	var yaw_to_send := player.body_visual.rotation.y
	var moving := player.velocity.length_squared() > 0.5
	var driving := current_vehicle != null
	if driving:
		position_to_send = current_vehicle.global_position
		yaw_to_send = current_vehicle.rotation.y
		moving = absf(current_vehicle.speed) > 0.5
	_send_online_message({
		"type": "state",
		"x": position_to_send.x,
		"y": position_to_send.y,
		"z": position_to_send.z,
		"yaw": yaw_to_send,
		"moving": moving,
		"driving": driving,
	})

func _send_online_message(message: Dictionary) -> void:
	if online_socket and online_socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		online_socket.send_text(JSON.stringify(message))

func _handle_online_message(message: Dictionary) -> void:
	var message_type := str(message.get("type", ""))
	match message_type:
		"welcome":
			online_peer_id = int(message.get("id", 0))
			player_username = str(message.get("username", player_username))
			online_mode = "online"
			_assign_local_factory(int(message.get("factory_slot", 0)))
			online_peers[online_peer_id] = {
				"username": player_username,
				"company": company_name,
				"color": brand_color.to_html(),
				"factory_slot": local_factory_slot,
			}
			var players = message.get("players", [])
			if players is Array:
				for player_data in players:
					if player_data is Dictionary:
						_receive_online_identity(player_data)
			_update_online_status()
			if not game_started:
				_finish_online_launch()
			else:
				_show_toast("Reconnected to the shared online world.")
		"auth_error":
			auth_token = ""
			_show_connection_failure(str(message.get("error", "Session expired. Sign in again.")))
		"world_full":
			_show_connection_failure(str(message.get("error", "Every factory plot is occupied.")))
		"player_joined":
			_receive_online_identity(message)
			_show_toast("%s joined the online world." % str(message.get("username", "A player")))
		"player_left":
			var departed_id := int(message.get("id", 0))
			var departed: Dictionary = online_peers.get(departed_id, {})
			var departed_name := str(departed.get("username", "A player"))
			online_peers.erase(departed_id)
			_remove_remote_peer(departed_id)
			_update_online_status()
			_show_toast("%s left the online world." % departed_name)
		"state":
			var peer_id := int(message.get("id", 0))
			if peer_id == 0 or peer_id == online_peer_id:
				return
			var remote_position := Vector3(
				float(message.get("x", 0.0)),
				float(message.get("y", 0.1)),
				float(message.get("z", 0.0))
			)
			_apply_remote_state(
				peer_id,
				remote_position,
				float(message.get("yaw", 0.0)),
				bool(message.get("moving", false)),
				bool(message.get("driving", false))
			)

func _receive_online_identity(player_data: Dictionary) -> void:
	var peer_id := int(player_data.get("id", 0))
	if peer_id == 0 or peer_id == online_peer_id:
		return
	var remote_username := str(player_data.get("username", "DRIVER")).left(18)
	var remote_company := str(player_data.get("company", "ONLINE MOTORS")).left(32)
	var remote_color_html := str(player_data.get("color", "1677ff"))
	var remote_factory_slot := int(player_data.get("factory_slot", -1))
	online_peers[peer_id] = {
		"username": remote_username,
		"company": remote_company,
		"color": remote_color_html,
		"factory_slot": remote_factory_slot,
	}
	_assign_factory_owner(peer_id, remote_factory_slot, remote_company, false)
	_spawn_remote_peer(peer_id, remote_username, remote_company, Color(remote_color_html), remote_factory_slot)
	if player_data.has("state") and player_data.state is Dictionary:
		var state: Dictionary = player_data.state
		_apply_remote_state(
			peer_id,
			Vector3(
				float(state.get("x", 0.0)),
				float(state.get("y", 0.1)),
				float(state.get("z", 0.0))
			),
			float(state.get("yaw", 0.0)),
			bool(state.get("moving", false)),
			bool(state.get("driving", false))
		)
	_update_online_status()

func _clear_online_session() -> void:
	for peer_id in remote_players.keys():
		_remove_remote_peer(int(peer_id))
	if online_peer_id != 0:
		_release_factory_owner(online_peer_id)
	online_peers.clear()
	online_socket = null
	online_peer_id = 0
	local_factory_slot = -1
	online_connected = false
	online_mode = "menu"
	_update_online_status()

func _update_online_status() -> void:
	if not online_status_label:
		return
	if online_mode == "menu":
		online_status_label.text = "OFFLINE"
		online_roster_panel.visible = false
		return
	var count := online_peers.size()
	if online_mode == "connecting":
		online_status_label.text = "ONLINE  •  CONNECTING…"
		online_roster_panel.visible = false
	else:
		online_status_label.text = "ONLINE  •  %d PLAYER%s" % [count, "" if count == 1 else "S"]
		online_roster_panel.visible = true
		var roster_lines := PackedStringArray(["PLAYERS ONLINE"])
		var peer_ids := online_peers.keys()
		peer_ids.sort()
		for peer_id in peer_ids:
			var identity: Dictionary = online_peers[peer_id]
			var marker := "YOU" if int(peer_id) == online_peer_id else "•"
			roster_lines.append("%s  %s  /  %s" % [
				marker,
				str(identity.get("username", "DRIVER")),
				str(identity.get("company", "ONLINE MOTORS")),
			])
		online_roster_label.text = "\n".join(roster_lines)
		online_roster_panel.size.y = 42 + maxi(1, count) * 24

func _spawn_remote_peer(peer_id: int, remote_username: String, remote_company: String, remote_color: Color, factory_slot: int) -> void:
	if peer_id == online_peer_id or remote_players.has(peer_id):
		return
	var remote := PlayerScript.new()
	remote.name = "OnlinePlayer_%d" % peer_id
	remote.configure_remote(remote_username, remote_company, remote_color)
	if factory_slot >= 0 and factory_slot < factory_slot_centers.size():
		remote.position = factory_slot_centers[factory_slot] + Vector3(-10, 0.1, -48)
	else:
		remote.position = Vector3(-86 if peer_id % 2 == 0 else 86, 0.1, 52)
	add_child(remote)
	remote.remote_target_position = remote.global_position
	remote_players[peer_id] = remote

func _remove_remote_peer(peer_id: int) -> void:
	_release_factory_owner(peer_id)
	if remote_players.has(peer_id):
		var remote: Node = remote_players[peer_id]
		if is_instance_valid(remote):
			remote.queue_free()
		remote_players.erase(peer_id)
	if remote_vehicles.has(peer_id):
		var remote_vehicle: Node = remote_vehicles[peer_id]
		if is_instance_valid(remote_vehicle):
			remote_vehicle.queue_free()
		remote_vehicles.erase(peer_id)

func _apply_remote_state(peer_id: int, remote_position: Vector3, remote_yaw: float, moving: bool, driving: bool) -> void:
	if not remote_players.has(peer_id) or not is_instance_valid(remote_players[peer_id]):
		return
	var remote: EmpirePlayer = remote_players[peer_id]
	remote.visible = not driving
	remote.apply_remote_state(remote_position, remote_yaw, moving)
	if driving:
		var remote_vehicle: EmpireVehicle
		if not remote_vehicles.has(peer_id) or not is_instance_valid(remote_vehicles[peer_id]):
			var identity: Dictionary = online_peers.get(peer_id, {"username": "DRIVER", "company": "ONLINE", "color": "1677ff"})
			remote_vehicle = VehicleScript.new()
			remote_vehicle.name = "OnlineVehicle_%d" % peer_id
			remote_vehicle.set_meta("online_remote", true)
			remote_vehicle.setup(self, Color(str(identity.color)), str(identity.company) + " CAR", 1)
			add_child(remote_vehicle)
			remote_vehicle.collision_layer = 0
			remote_vehicle.collision_mask = 0
			remote_vehicle.global_position = remote_position
			remote_vehicle.rotation.y = remote_yaw
			remote_vehicle.set_physics_process(false)
			remote_vehicles[peer_id] = remote_vehicle
		else:
			remote_vehicle = remote_vehicles[peer_id]
		remote_vehicle.visible = true
		remote_vehicle.global_position = remote_vehicle.global_position.lerp(remote_position, 0.6)
		remote_vehicle.rotation.y = lerp_angle(remote_vehicle.rotation.y, remote_yaw, 0.6)
	elif remote_vehicles.has(peer_id) and is_instance_valid(remote_vehicles[peer_id]):
		remote_vehicles[peer_id].visible = false
