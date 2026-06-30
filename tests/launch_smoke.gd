extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed := load("res://main.tscn") as PackedScene
	var game := packed.instantiate()
	root.add_child(game)
	await process_frame
	var username_input := LineEdit.new()
	username_input.text = "TestDriver"
	var company_input := LineEdit.new()
	company_input.text = "Test Motors"
	game.call("_launch_company", username_input, company_input)
	await process_frame
	var setup = game.get("company_setup")
	var setup_closed: bool = not is_instance_valid(setup) or not setup.visible
	var name_applied: bool = game.get("company_name") == "TEST MOTORS"
	var username_applied: bool = game.get("player_username") == "TestDriver"
	if setup_closed and name_applied and username_applied:
		print("LAUNCH_SMOKE_PASS")
		game.queue_free()
		await process_frame
		await process_frame
		quit(0)
	else:
		push_error("Company launch did not close setup or apply the company name.")
		game.queue_free()
		await process_frame
		quit(1)
