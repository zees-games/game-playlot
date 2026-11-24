extends "res://examples/headless_net_downed_ammo_flashlight.gd"

const PlaylotHullView := preload("../game/net/playlot_hull_view.gd")

const CHECKS := 468

## Sections entered against sections that ran to their last line, and against this. A
## runtime error inside a section aborts that function and nothing says so; a section that
## bailed out early after a failed guard is counted as not finished on purpose. The CHECKS
## total above is the other half — see docs/testing.md.
const SECTIONS := 55

func _ready() -> void:
	GSLog.set_level(GSLog.Level.ERROR)
	_run.call_deferred()


func _run() -> void:
	var errors := EngineErrors.new()
	OS.add_logger(errors)

	print("game-playlot — headless netcode")
	print("")

	_test_command_wire()
	_test_hull_view_wire()
	_test_event_wire()
	_test_inventory_wire()

	if await _build():
		await _connected_sequence_one()
		await _connected_sequence_two()

	_test_the_remote_workbench()

	OS.remove_logger(errors)
	# Engine errors go to stderr and change no exit code: a toy pulled out of the tree after a
	# mid-tick rebuild (gs-net history #30) printed `!is_inside_tree()` on green runs elsewhere.
	var seen := errors.seen()
	_check(seen.is_empty(), "the engine reported no error over the whole run",
		"%d: %s" % [seen.size(), ", ".join(seen.slice(0, 3))])

	_finish()


## From the handshake to the chat: the order is the suite's (both halves share one physics space).
func _connected_sequence_one() -> void:
	await _test_handshake()
	await _test_prediction()
	await _test_local_is_predicted()
	await _test_prop_replication()
	await _test_prop_request()
	await _test_tools()
	await _test_prop_removal()
	await _test_vehicle_over_the_wire()
	await _test_timer()
	await _test_lossy()
	# Both halves share one physics space, so a test that advances the world moves every later
	# reading. This one spawns no body; before the vehicle test it made that flake.
	await _test_weapon_request()
	await _test_multitool_wire()
	# Adds a second body to the shared physics space, and takes it back out.
	await _test_blind_and_beacon()
	# Adds a body to the shared world and takes it back out.
	await _test_somebody_else_is_drawn()
	_test_clock_wire()
	# Adds no body and moves nothing; it builds the services and takes them down again.
	await _test_chat_end_to_end()


## The inventory sections to the leave.
func _connected_sequence_two() -> void:
	# Before the inventory sections, whose bag it must not find a barrel in; the inventory
	# runs last of them because the rejoin takes the player's body out and back.
	await _test_refused_spawn_is_free()
	await _test_inventory_predicted()
	await _test_inventory_refused()
	await _test_inventory_lost()
	await _test_inventory_from_the_server()
	await _test_inventory_is_private()
	await _test_nothing_before_ready()
	await _test_inventory_flood()
	await _test_inventory_rejoin()
	await _test_zee_over_the_wire()
	await _test_toys_over_the_wire()
	# Last but the leave: it resizes the crate and spawns an NPC.
	await _test_tool_look_and_armed_npcs()
	# Adds no body: a grenade is a ray swept each tick, not a physics object.
	await _test_grenade_over_the_wire()
	await _test_own_grenade_predicted()
	await _test_utility_over_the_wire()
	# Spawns a platform and takes it out again; nothing after it but the leave.
	await _test_riding_over_the_wire()
	await _test_button_over_the_wire()
	await _test_builds_over_the_wire()
	await _test_edit_over_the_wire()
	await _test_map_props_over_the_wire()
	await _test_held_over_the_wire()
	await _test_glass_over_the_wire()
	await _test_swimming_over_the_wire()
	await _test_avatars_over_the_wire()
	# Arms a gun and puts it away again; adds no body.
	await _test_drawn_ammo_corrected()
	await _test_the_aim_bit_crosses()
	# Lays the player down and stands them up again; adds no body.
	await _test_downed_over_the_wire()
	await _test_the_flashlight_crosses()
	# The map's toys: kicks a ball and spins the roundabout, changes map and back. Last but
	# the leave, because a ball it kicks would be in the way of whatever came after.
	await _test_map_toys_over_the_wire()
	# Moves only the player's own body (noclip, then back); adds none.
	await _test_noclip_over_the_wire()
	await _test_grenade_for_a_joiner()
	await _test_movement_over_the_wire()
	await _test_leave()


func _finish() -> void:
	_report_sections(_entered, _completed, SECTIONS, CHECKS)

func _test_hull_view_wire() -> void:
	_section("a command names how the sender drew the others, and the server answers from a ring")
	var packet := PlaylotNetCommand.new()
	packet.tick = 500
	packet.view_lag_q = 37
	packet.view_back = 9
	packet.view_span = 2
	var writer := GSNetWriter.new()
	packet.write(writer)
	var back := PlaylotNetCommand.new()
	back.read(GSNetReader.new(writer.to_bytes()))
	_check(back.view_lag_q == 37 and back.view_back == 9 and back.view_span == 2, "the lag and the snapshot pair survive the wire", "%d %d %d" % [back.view_lag_q, back.view_back, back.view_span])
	var bare := PlaylotNetCommand.new()
	var bare_writer := GSNetWriter.new()
	bare.write(bare_writer)
	var bare_back := PlaylotNetCommand.new()
	bare_back.view_lag_q = 5
	bare_back.read(GSNetReader.new(bare_writer.to_bytes()))
	_check(bare_back.view_lag_q == -1 and bare_back.view_back == -1, "no view sent reads back as none")
	var huge := PlaylotNetCommand.new()
	huge.view_lag_q = 1 << 20
	huge.view_back = 1 << 20
	huge.view_span = 1 << 20
	huge._sanitise()
	_check(huge.view_lag_q == PlaylotNetCommand.MAX_VIEW_LAG_Q and huge.view_back < (1 << PlaylotNetCommand.VIEW_BACK_BITS) and huge.view_span < (1 << PlaylotNetCommand.VIEW_SPAN_BITS), "a hostile view is clamped to what the wire holds")
	back._neutralise()
	_check(back.view_lag_q == -1, "a silent player's view is cleared")
	_check(PlaylotHullView.session_of(&"u12") == 12, "a player key names its session")

	var holder := PlaylotHullView.new(null, null, true)
	var view := holder.view
	view.capacity = 4
	for tick in range(10, 16):
		view.record(tick, {&"u1": Vector3(float(tick), 0.0, 0.0), &"u2": Vector3(0.0, 0.0, float(tick))})
	_check(view.ring_at(&"u1", 15) != null and view.ring_at(&"u1", 11) == null, "the ring keeps capacity ticks and drops the older")
	var mid: Variant = view.ring_between(&"u1", 13, 14, 13.5)
	_check(mid != null and absf((mid as Vector3).x - 13.5) < 0.05, "a sample between two ticks is blended", str(mid))
	_check(view.ring_between(&"u1", 2, 3, 2.5) == null and int(view.counts["miss"]) == 1, "a tick the ring no longer holds is a counted miss")
	view.record(16, {&"u1": Vector3(500.0, 0.0, 0.0)})
	_check(view.ring_between(&"u1", 15, 16, 15.5) == null and int(view.counts["teleport"]) == 1, "a jump inside the pair is a teleport and the hull stays")
	_check(view.ring_at(&"u2", 16) == null, "a player who left keeps nothing")
	var aged := GSPlayerHullView.resolve(8, 100, 6, 2, 100)
	_check(is_equal_approx(aged[0], 98.0) and aged[1] == 98 and aged[2] == 2, "the render tick is the lag back from the step", str(aged))
	_done()
