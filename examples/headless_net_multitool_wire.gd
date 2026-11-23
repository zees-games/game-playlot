extends "res://examples/headless_net_props_and_tools.gd"

const PlaylotMultitool := preload("../game/playlot_multitool.gd")


## The multi-tool's mode over the wire: a mode the build does not have is refused out loud, a real one is the tool or weapon switch, and the switch lets go of what the old mode held.
func _test_multitool_wire() -> void:
	_section("the multi-tool: a mode is asked for, refused when unknown, and lets go of the prop")

	var player := _server_player()
	_check(player != null, "there is a player to arm")
	if player == null:
		return

	player.teleport(Vector3(-40.0, 0.0, -40.0), player.controller.state.yaw)
	await _steps(8)
	var at := player.eye_position() + player.aim_direction() * 2.5
	var crate := _server_game.props.spawn(&"crate", &"u%d" % SESSION, at)
	_check(crate != null, "a crate is put in front of them")
	if crate == null:
		return
	await _exchange_steps(4)

	_client_bridge.ask_multi_mode(&"phys")
	_exchange()
	await _steps(2)
	_check(player.multi_mode == PlaylotMultitool.index_of(&"phys"),
		"asking for the physics mode sets the replicated mode", str(player.multi_mode))

	var grab := GSFpsCommand.new()
	grab.set_button(GSFpsCommand.BUTTON_USER_0, true)
	_aim_at(grab, player, (crate.node as Node3D).global_position)
	await _steps(12, grab)
	_check(player.phys_gun.held != null, "the physics mode grabs the crate")

	# An id that is not a mode: refused with a notice, nothing changes, the prop stays held.
	var notices: Array[String] = []
	var on_notice := func(_pid: int, text: String) -> void: notices.append(text)
	_client_bridge.notice_received.connect(on_notice)
	var mode_before := player.multi_mode
	_client_bridge.ask_multi_mode(&"no_such_mode_at_all")
	_exchange()
	await _steps(4, grab)
	_exchange()
	await _steps(2, grab)
	_client_bridge.notice_received.disconnect(on_notice)
	_check(notices.size() > 0, "a mode that does not exist is answered with a notice", str(notices))
	_check(player.multi_mode == mode_before, "and the mode is unchanged", str(player.multi_mode))
	_check(player.phys_gun.held != null, "and the held prop is not let go by a refused ask")

	# A real switch lets go.
	_client_bridge.ask_multi_mode(&"grav")
	_exchange()
	await _steps(4, grab)
	_check(player.phys_gun.held == null, "switching to the gravity mode lets go of the held prop")
	_check(player.multi_mode == PlaylotMultitool.index_of(&"grav"),
		"and the replicated mode follows", str(player.multi_mode))

	var raised := GSFpsCommand.new()
	_client_bridge.ask_multi_raise(true)
	_exchange()
	await _steps(2, raised)
	_check(player.multi_raised, "raising the arm is replicated to the server's player")
	_client_bridge.ask_multi_raise(false)
	_exchange()
	await _steps(2, raised)
	_check(not player.multi_raised, "and lowering it too")

	await _spawn_mode_over_the_wire(player)

	_server_game.props.remove(crate.instance_id, GSPropSpawner.REASON_ADMIN)
	await _exchange_steps(4)
	_done()


## The Q menu's "Spawn with multi-tool" from a remote client: the pick is checked by the server, a bad
## one is refused out loud, and a held left button puts the item down where it aims, again and again.
func _spawn_mode_over_the_wire(player: PlaylotPlayer) -> void:
	var notices: Array[String] = []
	var on_notice := func(_pid: int, text: String) -> void: notices.append(text)
	_client_bridge.notice_received.connect(on_notice)
	_client_bridge.ask_arm(&"crate")
	_client_bridge.ask_multi_mode(&"spawn")
	_client_bridge.ask_multi_spawn("prop", &"barrel")
	await _exchange_steps(4)
	_exchange()
	await _steps(2)
	var toy: Variant = _server_bridge._toy_of.get(SESSION)
	_check(toy != null and toy.get(&"armed") == &"prop:barrel" and player.multi_mode == PlaylotMultitool.index_of(&"spawn"),
		"a remote 'Spawn with multi-tool' arms the server's spawn mode with the item", str(toy.get(&"armed") if toy != null else null))
	_client_bridge.ask_multi_spawn("prop", &"no_such_prop_at_all")
	_client_bridge.ask_multi_spawn("bogus_kind", &"crate")
	await _exchange_steps(4)
	_exchange()
	await _steps(2)
	_check(notices.size() >= 2 and toy != null and toy.get(&"armed") == &"prop:barrel",
		"an unknown item or kind is refused with a notice and the pick is kept", str(notices))

	var spawner := _server_game.props
	var before := spawner.player_count(player.player_id)
	var target := player.global_position + Vector3(player.aim_direction().x, 0.0, player.aim_direction().z).normalized() * 3.0
	var fire := GSFpsCommand.new()
	fire.set_button(GSFpsCommand.BUTTON_USER_0, true)
	_aim_at(fire, player, target)
	var every: float = _server_game.config.multi_spawn_repeat
	_server_game.config.multi_spawn_repeat = 0.1
	await _steps(15, fire)
	await _steps(2)
	_server_game.config.multi_spawn_repeat = every
	var mine := spawner.props_of(player.player_id)
	_check(mine.size() - before >= 2, "holding the left button puts the item down again at the repeat rate",
		"%d -> %d" % [before, mine.size()])
	# The first one lands on the aimed ground; the ones after pile up on it, back towards the player.
	var first: GSPropInstance = mine[before] if mine.size() > before else null
	var at := (first.node as Node3D).global_position if first != null else Vector3.INF
	_check(first != null and first.def.id == &"barrel" and Vector2(at.x - target.x, at.z - target.z).length() < 1.0,
		"and it is the armed item, put down where the player aims", "%s for %s" % [at, target])
	_check(spawner.undo(player.player_id) and spawner.player_count(player.player_id) == mine.size() - 1,
		"and the player's undo takes the last one back")
	for prop in spawner.props_of(player.player_id).slice(before):
		spawner.remove(prop.instance_id, GSPropSpawner.REASON_ADMIN)
	_client_bridge.notice_received.disconnect(on_notice)
	_client_bridge.ask_multi_mode(&"phys")
	await _exchange_steps(4)
