extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var is_client := OS.get_cmdline_user_args().has("--client")
	var packed := load("res://main.tscn") as PackedScene
	var game := packed.instantiate()
	root.add_child(game)
	await process_frame

	var auth_token := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--auth-token="):
			auth_token = argument.trim_prefix("--auth-token=")
	if auth_token.is_empty():
		push_error("Online smoke test requires --auth-token.")
		quit(1)
		return
	var username := "ClientDriver" if is_client else "HostDriver"
	var company := "CLIENT MOTORS" if is_client else "HOST MOTORS"
	game.call("_apply_account", {
		"username": username,
		"company": company,
		"color": "1677ff",
		"progress": {},
	})
	game.set("auth_token", auth_token)
	game.call("_show_loading_screen", "TEST CONNECTING")
	game.call("_connect_online_world")
	var local_player: EmpirePlayer = game.get("player")
	local_player.global_position = Vector3(-24.0 if is_client else 24.0, 0.1, 52.0)

	var passed := false
	for attempt in range(100):
		await create_timer(0.1).timeout
		var peers: Dictionary = game.get("online_peers")
		var remotes: Dictionary = game.get("remote_players")
		if peers.size() >= 2 and remotes.size() >= 1:
			var remote: EmpirePlayer = remotes.values()[0]
			var expected_x := 24.0 if is_client else -24.0
			var expected_username := "HostDriver" if is_client else "ClientDriver"
			if absf(remote.remote_target_position.x - expected_x) < 1.0 and remote.remote_username == expected_username:
				passed = true
				break

	if passed:
		print("ONLINE_SMOKE_PASS_", "CLIENT" if is_client else "HOST")
		await create_timer(1.0).timeout
	else:
		push_error("Online peers did not discover, show usernames, and synchronize position.")

	var socket = game.get("online_socket")
	if socket:
		socket.close()
	game.queue_free()
	await process_frame
	await process_frame
	quit(0 if passed else 1)
