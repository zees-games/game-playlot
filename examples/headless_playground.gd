extends "res://examples/headless_playground_part9.gd"

const CHECKS := 782 + 22 + 9 + 10 + 8 + 1 + 4 + 15 + 2 + 1 + 26 + 3 + 2 + 2 + 1 + 8 + 1 + 5 + 10 + 25 + 1 + 1 + 30 + 18 + 1 + 6 + 3 + 1 + 2 + 1 + 8 + 4 + 5 + 3 + 1
const PlaygroundClientPrewarm := preload("res://game/client/playground_client_prewarm.gd")

## Sections entered against sections that ran to their last line, and against this. A
## runtime error inside a section aborts that function and nothing says so; a section that
## bailed out early after a failed guard is counted as not finished on purpose. The CHECKS
## total above is the other half — see docs/testing.md.
const SECTIONS := 46

## What `_test_the_run_timer` and `_test_leaderboards` add when dot-timer is linked.
const TIMER_SECTIONS := 2
const TIMER_CHECKS := 14

func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	# The real `PlaygroundClient`s below each build a presentation layer, and that layer's
	# settings go to a scratch directory emptied first, never the player's own file (see
	# `PlaygroundPresentation.use_scratch_settings`).
	var _scratch := PlaygroundPresentation.use_scratch_settings("headless_playground")
	_run.call_deferred()


func _run() -> void:
	print("playground — headless integration")
	print("")

	await _boot()
	if await _run_only():
		return

	await _test_boots()
	await _test_tick_rate_comes_from_the_engine()
	await _test_styles()
	# The two that need dot-timer, run only when linked; skipped, they add to neither total.
	if _timer_linked():
		await _test_the_run_timer()
		await _test_leaderboards()
	else:
		print("")
		print("  SKIP  the run timer and its leaderboards: res://addons/dot_timer is not linked")
	await _test_props()
	await _test_map_change()
	await _test_map_time_limit()
	await _test_props_are_built_from_their_definitions()
	await _test_model_props()
	await _test_entities_run_their_scripts()
	await _test_profiles()
	await _test_profile_workbench()
	await _test_weapons()
	await _test_zee_weapons()
	await _test_zee_aim()
	await _test_limits_per_kind()
	await _test_the_tool_gun()
	await _test_armed_npcs()
	await _test_addon_hook_and_npc_tools()
	await _test_spawn_providers()
	await _test_grenades()
	await _test_spawn_menu()
	await _test_workshop()
	await _test_vehicles()
	await _test_picking_players_up()
	await _test_riding_a_moving_prop()
	await _test_breaking_props()
	await _test_buttons_and_doors()
	await _test_saved_builds()
	await _test_editing_a_selected_prop()
	await _test_the_maps_are_surveyed()
	await _test_drawn_worlds()
	await _test_nothing_drawn_is_walked_through()
	await _test_a_maps_own_props()
	await _test_toys()
	await _test_every_maps_toys_stand_clear()
	await _test_map_materials()
	await _test_glass()
	await _test_water()
	await _test_ice_slime_foliage()
	await _test_camera_motion()
	await _test_the_client_boots()
	await _test_the_wheel_cycles_tools()
	await _test_noclip_is_a_permission()
	await _test_the_flashlight()
	_test_view_cycle()

	var sections := SECTIONS + (TIMER_SECTIONS if _timer_linked() else 0)
	var checks := CHECKS + (TIMER_CHECKS if _timer_linked() else 0) - _tmas_unsurveyed_checks
	_report_sections(_entered, _completed, sections, checks)


## The playground, on the flat map, with records in memory.
func _boot() -> void:
	playground = Playground.new()

	var config := PlaygroundConfig.new()
	# Records in memory: a headless run must not write into the user's data directory.
	config.records_directory = ""
	# No map on boot: the tests below load their own and would race a boot load.
	config.initial_map = &"pg_flatgrass"
	config.map_seconds = 0.0
	playground.config = config

	add_child(playground)

	# Two frames: `_ready` awaits its first map change, so one is not enough to finish booting.
	await get_tree().process_frame
	await get_tree().process_frame


	# `-- --only=<method>` runs the boot and that one section, for working on it: nothing
	# else runs, so the totals are not checked and the exit code is the section's alone.
## Returns whether it was asked for, and then has run and quit.
func _run_only() -> bool:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			await _test_boots()
			await Callable(self, arg.substr(7)).call()
			print("")
			print("ONLY %s: %d passed, %d failed (totals not checked)" % [arg.substr(7), _passed, _failed])
			for line in _failures:
				print("  FAIL  %s" % line)
			get_tree().quit(1 if _failed > 0 else 0)
			return true
	return false


## Whether a point is over a box seen from above.
static func _over(at: Vector3, box: AABB) -> bool:
	return (
		at.x >= box.position.x and at.x <= box.end.x
		and at.z >= box.position.z and at.z <= box.end.z
	)


## One tick's motion into [param tally]. A tick that moved further than any run can, a
## metre sideways or up or down in 1/128 s, is a respawn's teleport and is left out.
static func _tally_tick(tally: Dictionary, before: Vector3, after: Vector3, where: String) -> void:
	var flat := Vector2(after.x - before.x, after.z - before.z).length()
	var dy := after.y - before.y

	if flat >= 1.0 or absf(dy) >= 1.0:
		return

	var bucket: Dictionary = tally[where]
	bucket["distance"] = float(bucket["distance"]) + flat
	bucket["ticks"] = int(bucket["ticks"]) + 1

	if dy < 0.0:
		bucket["descent"] = float(bucket["descent"]) - dy
	else:
		bucket["ascent"] = float(bucket["ascent"]) + dy


## The sum of one field over all three parts of [param tally].
static func _tally_total(tally: Dictionary, field: String) -> float:
	var total := 0.0
	for where in tally:
		total += float((tally[where] as Dictionary)[field])
	return total


## Prints where [param tally]'s ground and descent happened, against the route's own net
## rise ([param route_rise]). [param surface] names what the route is about.
func _print_where(route_name: String, surface: String, tally: Dictionary, route_rise: float) -> void:
	var covered := _tally_total(tally, "distance")
	var descent := _tally_total(tally, "descent")
	var ascent := _tally_total(tally, "ascent")
	var part := func(field: String, where: String, total: float) -> String:
		var value := float((tally[where] as Dictionary)[field])
		return "%.1f (%.0f%%)" % [value, 100.0 * value / maxf(total, 0.001)]

	print("    %s, where the ground went: %.1f m covered: %s on %s, %s in the air, %s on anything else" % [
		route_name, covered, part.call("distance", "on", covered), surface,
		part.call("distance", "air", covered), part.call("distance", "else", covered),
	])
	print("    %s, where the descent came from: %.1f m down (%.1f up, net %+.1f against the route's %+.1f): %s on %s, %s in the air, %s on anything else" % [
		route_name, descent, ascent, ascent - descent, route_rise,
		part.call("descent", "on", descent), surface,
		part.call("descent", "air", descent), part.call("descent", "else", descent),
	])


## The length of a route of boxes as a bot that took every jump straight covers it:
## [param from] to the first box after the pad, then centre to centre, along the ground.
static func _route_length(from: Vector3, route: Array[AABB]) -> float:
	var length := 0.0
	for i in range(1, route.size()):
		var to := route[i].get_center()
		length += Vector2(to.x - from.x, to.z - from.z).length()
		from = to
	return length


## `[bot-drive-1]`: the drive covered at least [param covered_floor] of the route, at a
## pace of at least [param pace_floor] of [param max_speed]. The floors are per route and
## set just under what the bot measured (2026-09-27), because a route with many jumps
## spends time in the air where a bot cannot hold its ground speed; a bot crawling at 40%
## of its speed fails every one of them.
func _check_pace(
	route_name: String, covered: float, length: float, pace: float, max_speed: float,
	pace_floor: float, covered_floor: float = 0.9
) -> void:
	_check(
		covered >= length * covered_floor and pace >= max_speed * pace_floor,
		"%s is covered at a running pace, not a crawl (%.0f%% of the route, %.0f%% of max speed or more)"
			% [route_name, covered_floor * 100.0, pace_floor * 100.0],
		"%.1f m of %.1f at %.2f m/s against %.1f" % [covered, length, pace, max_speed]
	)


## `[surf-ramp-1]`: none of the ground and none of the descent of a drive happened on
## something other than the route's own surface or the air above it.
func _check_where(route_name: String, surface: String, tally: Dictionary) -> void:
	var elsewhere: Dictionary = tally["else"]
	_check(
		float(elsewhere["distance"]) < 1.0 and float(elsewhere["descent"]) < 0.1,
		"%s is run on its %s and the air between them, and nothing else" % [route_name, surface],
		"%.1f m and %.2f m of descent on something else"
			% [float(elsewhere["distance"]), float(elsewhere["descent"])]
	)


## `[bot-drive-1]`: prints "covered X of Y m in T s: V m/s against a max" and returns V.
func _print_pace(
	route_name: String, covered: float, length: float, ticks: int, max_speed: float,
	top: float
) -> float:
	var seconds := float(ticks) / float(Engine.physics_ticks_per_second)
	var pace := covered / maxf(seconds, 0.001)
	print("    %s: covered %.1f m of a %.1f m route in %.2f s: %.2f m/s against a %.1f m/s max, top %.2f" % [
		route_name, covered, length, seconds, pace, max_speed, top,
	])
	return pace


func _test_the_client_boots() -> void:
	_section("the client boots")

	_tcb_client = PlaygroundClient.new()
	_tcb_client.name = "Client"
	_tcb_client.fetch_content = false

	# Its own config, records in memory. A test must not write into the user's data
	# directory, and this is the only reason `PlaygroundClient.config` exists.
	var config := PlaygroundConfig.new()
	config.records_directory = ""
	config.record_replays = false
	_tcb_client.config = config

	add_child(_tcb_client)

	for _i in range(4):
		await get_tree().process_frame

	# The load gate covers the client, and holds its input and its body, until the level, the
	# player and the camera are in and the physics has settled: a test that drives the
	# client waits for it as a player would.
	await _gate_opens(_tcb_client)
	_check(_tcb_client.gate != null and _tcb_client.gate.is_open(), "the load gate opens once the level, player and camera are in",
		"state %s held %s" % [_tcb_client.gate.state(), _tcb_client.gate.reasons()] if _tcb_client.gate != null else "no gate")
	_the_warmup_ran_under_the_cover()
	_check(_tcb_client.playground != null, "the client builds a playground")
	_check(
		_tcb_client.playground != null and _tcb_client.playground.booted,
		"which finishes booting"
	)
	_check(
		_tcb_client.playground != null and _tcb_client.playground.maps.current != null,
		"with a map up",
		String(_tcb_client.playground.maps.current.id)
			if _tcb_client.playground != null and _tcb_client.playground.maps.current != null
			else "none"
	)

	# The four things that are all missing together when `_ready` stops halfway.
	_check(_tcb_client.player != null, "the client has a player")
	_check(_tcb_client.camera != null, "and a camera")
	_check(_tcb_client.hud != null, "and a HUD")
	_check(
		_tcb_client.screens != null and _tcb_client.menu != null,
		"and a spawn menu registered on a stack"
	)

	_check(
		_tcb_client.menu != null and _tcb_client.screens != null
		and _tcb_client.screens.screen(_tcb_client.menu.screen_id()) == _tcb_client.menu,
		"which the stack can find by id"
	)
	_check(
		_tcb_client.player != null and _tcb_client.player.samples_input
		and _tcb_client.player.sampler != null,
		"and the player samples input, with a sampler actually built"
	)
	_the_client_mounts_the_downed_arms()
	await _test_the_client_boots_2()
	await _test_the_client_boots_3()
	await _test_the_client_boots_4()
	_test_the_client_boots_5()
	await _test_the_client_boots_6()
	await _test_the_client_boots_7()
	await _test_the_client_boots_8()
	await _test_the_client_boots_12()
	await _test_the_client_boots_13()
	_tcb_client = null
	_tcb_look_settings = null
	_tcb_look = null
	_tcb_net_sampler = null
	_tcb_kept_menu = null
	_tcb_keys = null
	_tcb_menu = null
	_tcb_pg_hud = null
	_tcb_pg_xh = null
	_tcb_sink = null
	_tcb_edited = null


## What the first spawn, shot and menu would build in play was built under the load cover, and
## nothing of it was left in the world.
func _the_warmup_ran_under_the_cover() -> void:
	var warm: Variant = _tcb_client.prewarm
	_check(warm != null and warm.finished and warm.warmed > 0 and not _tcb_client.gate.is_holding(&"prewarm"),
		"the warm-up ran under the cover and let go of it", "warm-up %s" % [warm.phase_ms if warm != null else "missing"])
	_check(_tcb_client.gate.warm_items().size() > 0,
		"and handed the gate what NPCs, weapons and effects draw (%d items)" % _tcb_client.gate.warm_items().size())
	_check(warm != null and warm.get_child_count() == 0, "and kept none of what it built")
	_check(warm != null and warm.hid_world and not _tcb_client.get_viewport().disable_3d,
		"and left the world undrawn under the cover, then drew it again", "hid %s" % [warm.hid_world if warm != null else "?"])
	var keys := {}
	var twice := 0
	for item: Variant in _tcb_client.gate.warm_items():
		var key: String = DotRenderWarmup.item_key(item)
		if key != "" and keys.has(key):
			twice += 1
		keys[key] = true
	_check(twice == 0 and warm != null and warm.skipped > 0,
		"and handed each shader once (%d alike left out)" % [warm.skipped if warm != null else 0], "%d handed twice" % twice)
	var cam: Camera3D = _tcb_client.get_viewport().get_camera_3d()
	_check(not _tcb_client.gate.is_open() or cam == null or cam.get_node_or_null(^"PrewarmLightProbe") == null,
		"and took its light off the camera once the gate opened")
	var on := PlaygroundConfig.new()
	var soft_on := PlaygroundConfig.new()
	soft_on.prewarm_shot_effects_software = true
	var wants: Callable = func(c: PlaygroundConfig) -> bool:
		var probe := PlaygroundClientPrewarm.new()
		probe.config = c
		var out: bool = probe._shot_effects()
		probe.free()
		return out
	var soft := PlaygroundClientPrewarm.is_software_renderer()
	_check(on.prewarm_shot_effects and wants.call(on) == (not soft) and wants.call(soft_on),
		"and warms the first shot's flash and light by default, on a software rasteriser only when asked",
		"software %s, default %s, asked %s" % [soft, wants.call(on), wants.call(soft_on)])


func _test_the_maps_are_surveyed() -> void:
	print("")
	_section("the hand-built maps, surveyed for slots, unreached ground and traps")

	_the_survey_sees_what_it_looks_for()

	for id in _built_map_ids():
		var script := load("res://maps/%s.gd" % id) as GDScript
		var map: Node3D = script.new()
		map._build()

		# The map brings its light with it (`PlaygroundGeometry.light`): exactly one sun and
		# one environment, or the second is silently ignored by the renderer. dot-lighting's
		# shadowless `Fill` (painted()) is not a second sun.
		var suns := map.get_children().filter(func(n: Node) -> bool: return n is DirectionalLight3D and n.name != "Fill").size()
		var skies := map.get_children().filter(func(n: Node) -> bool: return n is WorldEnvironment).size()
		_check(suns == 1 and skies == 1, "%s: carries one sun and one sky (its dot-lighting document)" % id,
			"%d suns, %d environments" % [suns, skies])

		# A hand-built map here declares no zones (a run timer's, when a server has one,
		# come from the map document or zone file), so its ways out are its walls and
		# floor alone.
		var spawns: Array[Vector3] = [map.fallback_spawn]

		var declared: Array = map.survey_declared()
		var started := Time.get_ticks_msec()
		var found: Dictionary = PlaygroundMapSurvey.survey(map, [], spawns, declared)
		map.free()

		print("    %s: %d standable cells in %d regions, %d spawns, %d declared, %d falls into nothing, %d ms" % [
			id, int(found["cells"]), int(found["regions"]), spawns.size(), declared.size(),
			int(found["void_falls"]), Time.get_ticks_msec() - started,
		])

		_check((found["spawnless"] as Array).is_empty(),
			"%s: every spawn stands on standable ground" % id,
			", ".join(found["spawnless"]))
		_check((found["slots"] as Array).is_empty(),
			"%s: no two boxes leave a slot narrower than a player" % id,
			"; ".join(found["slots"]))
		_check((found["unreached"] as Array).is_empty(),
			"%s: nothing standable is out of reach of every spawn, but what it declares" % id,
			"; ".join(found["unreached"]))
		_check((found["trapped"] as Array).is_empty(),
			"%s: and nowhere a spawn reaches is a place with no way out" % id,
			"; ".join(found["trapped"]))

	# The custom maps playlot-maps delivers, linked in as `maps/custom`. Named rather
	# than listed off the directory, so a checkout without the link fails here instead of
	# surveying nothing and passing.
	_tmas_data_script = load("res://maps/pg_data.gd") as GDScript
	_test_the_maps_are_surveyed_2()
