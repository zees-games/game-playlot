extends DotGameCheckSuite

const Playground := preload("../game/playground.gd")
const PlaygroundConfig := preload("../game/playground_config.gd")
const NpcSoldier := preload("../game/entities/npc_soldier.gd")

## An armed NPC's idle weapon tick: the rig's own idle tick (no context, no wall probe) against
## the full tick with a built context, on twin soldiers fed the same seeded trigger pattern.
## Every tick both rigs' snapshots (arsenal, RNG, cooldowns, previous buttons) must agree.
## Run: godot --headless --path . res://examples/headless_npc_weapon_idle.tscn

const SECTIONS := 1
const WEAPONS: Array[StringName] = [&"zee_smg", &"zee_pistol", &"zee_shotgun", &"zee_rifle"]
const TICKS := 480
const CHECKS := 3 + 3 * 4 + 2

var _entered := 0
var _completed := 0
var _game: Playground = null


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run.call_deferred()


func _run() -> void:
	print("game-playground: armed NPC idle weapon tick")
	_game = await _make_game()
	await _test_parity()
	NpcSoldier.idle_rig_ticks = true
	_report_sections(_entered, _completed, SECTIONS, CHECKS)


func _make_game() -> Playground:
	var config := PlaygroundConfig.new()
	config.records_directory = ""
	config.map_seconds = 0.0
	config.initial_map = &"pg_flatgrass"
	config.authoritative = true
	config.prop_spawn_interval = 0.0
	var game := Playground.new()
	game.name = "Server"
	game.config = config
	game.service_scope = &"npc_idle_server"
	add_child(game)
	for _i in range(120):
		await get_tree().process_frame
		if game.maps != null and game.maps.current != null:
			break
	return game


func _soldier(at: Vector3) -> Node:
	var made := _game.props.spawn(&"npc_soldier", &"bot", at)
	if made == null:
		return null
	var body := made.node
	# Out of the simulation: the brain does not think, so the test alone sets the trigger.
	body.set("_dead", true)
	return body


func _test_parity() -> void:
	_entered += 1
	print("Idle tick against full tick")
	_game.spawn_player(&"bot")
	_game.props.limits.spawn_interval = 0.0
	var a := _soldier(Vector3(-40.0, 1.2, -40.0))
	var b := _soldier(Vector3(40.0, 1.2, 40.0))
	_check(a != null and b != null, "two soldiers spawn")
	if a == null or b == null:
		return
	for _i in range(30):
		await get_tree().physics_frame
	_check(a.call("is_armed") and b.call("is_armed"), "both are armed")
	_check(NpcSoldier.idle_rig_ticks, "the idle tick is on by default")

	var rng := RandomNumberGenerator.new()
	var all_idle := 0
	# Both paths timed in the same process every tick, so box load falls on both alike. The two
	# soldiers swap roles each weapon and take turns going first in a tick (the first pays the
	# tick's one-off costs), so neither soldier's own costs land on one side. Medians, as a loaded
	# box puts a few long stalls on either side.
	var idle_on_list: Array[int] = []
	var idle_off_list: Array[int] = []
	var full_on_list: Array[int] = []
	var full_off_list: Array[int] = []
	for w in range(WEAPONS.size()):
		var weapon: StringName = WEAPONS[w]
		var on: Node = a if w % 2 == 0 else b
		var off: Node = b if w % 2 == 0 else a
		rng.seed = hash(String(weapon))
		var armed_a: DotResult = a.call("arm_with", weapon)
		var armed_b: DotResult = b.call("arm_with", weapon)
		_check(armed_a.ok and armed_b.ok, "%s: both hold it" % weapon)
		var mismatch := -1
		var detail := ""
		var fire := false
		var run_left := 0
		var idle_before: int = on.get("idle_ticks")
		var off_before: int = off.get("idle_ticks")
		for tick in range(TICKS):
			if run_left <= 0:
				fire = not fire
				run_left = rng.randi_range(1, 60)
			run_left -= 1
			for body: Node in [a, b]:
				var brain: Object = body.get("brain")
				brain.set("wants_fire", fire)
				brain.set("aim_at", (body as Node3D).global_position + Vector3(0.0, 30.0, 10.0))
			var idle_was: int = on.get("idle_ticks")
			var spent := _timed_drive(on, off, tick)
			var spent_on: int = spent.x
			var spent_off: int = spent.y
			if int(on.get("idle_ticks")) > idle_was:
				idle_on_list.append(spent_on)
				idle_off_list.append(spent_off)
			else:
				full_on_list.append(spent_on)
				full_off_list.append(spent_off)
			var sa: Dictionary = (a.get("zee_rig") as ZeeWeaponRig).snapshot()
			var sb: Dictionary = (b.get("zee_rig") as ZeeWeaponRig).snapshot()
			if mismatch < 0 and var_to_str(sa) != var_to_str(sb):
				mismatch = tick
				detail = "tick %d: %s vs %s" % [tick, var_to_str(sa), var_to_str(sb)]
			await get_tree().physics_frame
		var idled: int = int(on.get("idle_ticks")) - idle_before
		all_idle += idled
		_check(mismatch < 0, "%s: every tick's rig snapshot agrees" % weapon, detail)
		_check(idled > 0 and int(off.get("idle_ticks")) == off_before, "%s: the idle tick was taken (%d ticks), only where on" % [weapon, idled])
	_check(all_idle < TICKS * WEAPONS.size(), "and the full tick still ran when firing")
	var idle_on := _median(idle_on_list)
	var idle_off := _median(idle_off_list)
	print("  weapon drive, median us a call: idle ticks (%d) %d with the idle tick, %d without; firing ticks %d vs %d" % [
		idle_on_list.size(), idle_on, idle_off, _median(full_on_list), _median(full_off_list)])
	_check(idle_on < idle_off, "the idle tick costs less than the full one it replaces (%d vs %d us)" % [idle_on, idle_off])
	_completed += 1


## One tick's weapon drive on [param on] with the idle tick and on [param off] without, in alternating order each tick; the microseconds each took, as (on, off).
func _timed_drive(on: Node, off: Node, tick: int) -> Vector2i:
	var spent := Vector2i.ZERO
	for on_now: bool in ([true, false] if tick % 2 == 0 else [false, true]):
		NpcSoldier.idle_rig_ticks = on_now
		var t0 := Time.get_ticks_usec()
		(on if on_now else off).call("_drive_weapon")
		var took := Time.get_ticks_usec() - t0
		if on_now:
			spent.x = took
		else:
			spent.y = took
	NpcSoldier.idle_rig_ticks = true
	return spent


static func _median(values: Array[int]) -> int:
	if values.is_empty():
		return 0
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[sorted.size() / 2]
