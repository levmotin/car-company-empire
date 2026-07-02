extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed := load("res://main.tscn") as PackedScene
	var game := packed.instantiate()
	root.add_child(game)
	await process_frame
	var menu = game.get("company_setup")
	var menu_visible: bool = is_instance_valid(menu) and menu.visible
	var google_only_auth: bool = false
	var password_fields_removed: bool = true
	if is_instance_valid(menu):
		for node in menu.find_children("*", "Button", true, false):
			if node is Button and node.text == "SIGN IN OR SIGN UP WITH GOOGLE":
				google_only_auth = true
		password_fields_removed = menu.find_children("*", "LineEdit", true, false).is_empty()
	var minimap_removed: bool = game.get("hud").find_child("*CITY NAVIGATION*", true, false) == null
	var drive_through_ready: bool = false
	var drive_through_terminals := 0
	for item in game.get("interactables"):
		if str(item.get_meta("kind", "")).begins_with("burger_"):
			drive_through_terminals += 1
			drive_through_ready = drive_through_ready or bool(item.get_meta("allow_vehicle", false))
	game.call("_apply_account", {
		"username": "TestDriver",
		"company": "Test Motors",
		"color": "1677ff",
		"progress": {
			"money": 54321,
			"reputation": 10,
			"company_level": 2,
			"research": 1,
			"inventory": {"Chassis": 2, "Engine": 3, "Transmission": 4, "Wheels": 5, "Electronics": 6},
			"cars": [{"name": "TEST GT", "quality": 4, "color": "ff6333"}],
			"total_built": 2,
			"total_sales": 1,
			"objective_stage": 3,
			"player_position": {"x": 90, "y": 0.1, "z": 55},
		},
	})
	game.set("auth_token", "test-token")
	game.call("_show_main_menu")
	await process_frame
	var authenticated_menu_ready: bool = not game.get("game_started") and not game.get("hud").visible
	game.call("_place_drive_through_order", "TEST COMBO", 18)
	var order_placed: bool = game.get("drive_through_order") == "TEST COMBO" and game.get("money") == 54303
	game.call("_collect_drive_through_order")
	var order_collected: bool = game.get("drive_through_order") == "" and game.get("reputation") == 13
	game.set("online_peer_id", 101)
	game.call("_assign_local_factory", 0)
	game.call("_assign_factory_owner", 202, 1, "REMOTE MOTORS", false)
	var factory_centers: Array[Vector3] = game.get("factory_slot_centers")
	var factory_plots: Array[Node3D] = game.get("factory_plots")
	var unique_factories_ready: bool = (
		factory_centers.size() == 12
		and factory_plots.size() == 12
		and game.get("player").global_position.distance_to(factory_centers[0] + Vector3(-10, 0.1, -48)) < 0.1
		and int(factory_plots[0].get_meta("owner_peer_id")) == 101
		and int(factory_plots[1].get_meta("owner_peer_id")) == 202
	)
	game.call("_finish_online_launch")
	await process_frame
	var setup = game.get("company_setup")
	var setup_closed: bool = not is_instance_valid(setup) or not setup.visible
	var name_applied: bool = game.get("company_name") == "TEST MOTORS"
	var username_applied: bool = game.get("player_username") == "TestDriver"
	var money_loaded: bool = game.get("money") == 54303
	var cars_loaded: bool = game.get("manufactured_vehicles").size() == 1
	if menu_visible and google_only_auth and password_fields_removed and authenticated_menu_ready and order_placed and order_collected and unique_factories_ready and minimap_removed and drive_through_ready and drive_through_terminals == 2 and setup_closed and name_applied and username_applied and money_loaded and cars_loaded:
		print("LAUNCH_SMOKE_PASS")
		game.queue_free()
		await process_frame
		await process_frame
		quit(0)
	else:
		push_error("Online account launch did not restore the saved company.")
		game.queue_free()
		await process_frame
		quit(1)
