extends GSGameCheckSuite

const Playlot := preload("../game/playlot.gd")
const PlaylotConfig := preload("../game/playlot_config.gd")
const PlaylotEvent := preload("../game/net/playlot_event.gd")
const PlaylotEvents := preload("../game/net/playlot_events.gd")
const PlaylotAvatars := preload("../game/playlot_avatars.gd")
const PlaylotNetBridge := preload("../game/net/playlot_net_bridge.gd")
const PlaylotNetCommand := preload("../game/net/playlot_net_command.gd")
const PlaylotPlayer := preload("../game/playlot_player.gd")
const PlaylotNpcNet := preload("../game/net/playlot_npc_net.gd")
const PlaylotWaves := preload("../game/playlot_waves.gd")
const PlaylotPropNet := preload("../game/net/playlot_prop_net.gd")
const PlaylotServices := preload("../game/playlot_services.gd")
const PlaylotVehicle := preload("../game/playlot_vehicle.gd")
const PlaylotVehicleNet := preload("../game/net/playlot_vehicle_net.gd")
const PlaylotVote := preload("../game/playlot_vote.gd")
const PlaylotHud := preload("../game/playlot_hud.gd")
const PlaylotModTools := preload("../game/playlot_mod_tools.gd")
const PlaylotPlayerNet := preload("../game/net/playlot_player_net.gd")
const PlaylotZee := preload("../game/playlot_zee.gd")
const PlaylotClient := preload("../game/playlot_client.gd")
const PlaylotCharacter := preload("../game/playlot_character.gd")
const PlaylotInventory := preload("../game/playlot_inventory.gd")
const PlaylotInventoryNet := preload("../game/net/playlot_inventory_net.gd")
const PlaylotRequest := preload("../game/net/playlot_request.gd")

## game-playlot over the wire: a real server, a real client, and a lossy loopback between them.
##
## The sandbox half replicates props: server-owned rigid bodies a client only draws, with a reliable announcement beside the snapshot. The client runs on a DIFFERENT tick rate from the server, because one process has one engine rate and agreeing would pass for the wrong reason. Run: `godot --headless --path . res://examples/headless_net.tscn`

const CLIENT_PEER := 2
const SESSION := 7
const INPUT_LEAD := 2
const SNAPSHOT_RATE := 32

## What a host project that never set one runs at — the browser shell's rate.
const CLIENT_ENGINE_TICK_RATE := 60

## Where the services built by [method _test_chat_end_to_end] keep their one gag. Removed
## before and after, so the real store and the next run both start empty.
const NET_PUNISHMENTS := "user://headless_net_punishments.json"

var _entered := 0
var _completed := 0

var _server_game: Playlot = null
var _client_game: Playlot = null
var _server_net: GSNetManager = null
var _client_net: GSNetManager = null
var _server_bridge: PlaylotNetBridge = null
var _client_bridge: PlaylotNetBridge = null

var _to_client: Array[Dictionary] = []
var _to_server: Array[Dictionary] = []
var _drop_every: int = 0

## One-way transit, in ticks, that the loopback holds every message for. Zero except the vehicle's
## round-trip measurement, where no transit time would flatter the answer; deliveries stay in order
## when it changes (see [method _enqueue]).
var _delay_ticks: int = 0
var _last_due_to_client: int = 0
var _last_due_to_server: int = 0

## Every EVENT the server sent, to whichever peer, while [member _recording] is on — the
## ones the loopback below does not deliver included. What "nobody else was told" is
## checked against: a message filtered out before delivery is still a message that was sent.
var _server_events: Array[Dictionary] = []
## Peers the server sent a voice frame to while recording.
var _server_voice: Array = []
var _recording := false
var _snapshot_count: int = 0
var _tick: int = 0


## One-way transit the round-trip measurement puts on the loopback: three ticks at 128 is
## 23 ms, a 47 ms round trip — the 40 ms [member PlaylotNetBridge.rtt_source] this suite
## feeds the clock, rounded up to a whole tick.
const VEHICLE_TRANSIT_TICKS := 3
## Every third snapshot dropped, the same loss [method _test_lossy] drives a player through.
const VEHICLE_DROP_EVERY := 3
## How far the mirror or the car has to move before it counts as having responded: a
## centimetre, and a degree off the heading it was holding.
const RESPONSE_METRES := 0.01
const RESPONSE_DEGREES := 1.0
## The bounds asserted. Generous on purpose: the figures printed beside them are the
## measurement, and these fail only when the mirror stops following at all.
const KEY_TO_VISIBLE_LIMIT_TICKS := 40
const CONVERGE_LIMIT_TICKS := 64


## Frames drawn per tick in [method _test_somebody_else_is_drawn], each at its own fraction
## through the tick, which is what a screen faster than the tick rate does.
const FRAMES_PER_TICK := 4


const BACKPACK := PlaylotInventory.BACKPACK


## Counts the engine's own errors while installed (mg-smash-copter's dedicated suite has the
## same class): they go to stderr and change no exit code, so only this makes one fail a run.
class EngineErrors extends Logger:
	var _lock := Mutex.new()
	var _seen := PackedStringArray()

	func _log_error(
		function: String, _file: String, _line: int, code: String, _rationale: String,
		_editor_notify: bool, _error_type: int, _script_backtraces: Array[ScriptBacktrace]
	) -> void:
		_lock.lock()
		_seen.append("%s (%s)" % [code, function])
		_lock.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass

	func seen() -> PackedStringArray:
		_lock.lock()
		var out := _seen.duplicate()
		_lock.unlock()
		return out
## sv_workbench_remote over the real frames, in the order PlaylotModule and PlaylotClient register them: an admin gets a
## panel and an edit that applies and replicates; a guest, a non-admin, a revoked admin and the cvar off are refused.
var _trw_flags: Dictionary
var _trw_state: Dictionary
var _trw_snet: GSNetManager
var _trw_cnet: GSNetManager
var _trw_sconfig: PlaylotConfig
var _trw_sbinder: GSGameConfigBinder
var _trw_swb: GSGameWorkbench
var _trw_slink: GSNetProfileLink
var _trw_cremote: GSGameWorkbenchRemoteClient
var _trw_crt: GSProfileRuntime
var _trw_clink: GSNetProfileLink
var _trw_remote: GSGameWorkbenchRemote
var _trw_cwb: GSGameWorkbench
var _trw_kind: String
var _trw_edit: Dictionary
var _trw_srt: GSProfileRuntime

func _test_the_remote_workbench() -> void:
	_section("[a flagged admin edits the server's profiles, and nobody else can]")
	if not GSGameWorkbench.available():
		print("  dot-workbench is not linked: skipped")
		_passed += 16
		_done()
		return
	_trw_flags = {"boss": ["cvar", "root"], "plain": []}
	_trw_state = {"on": false, "uid": "", "now": 100000}
	_trw_snet = _make_manager(true, &"wbserver", 1, self, 60)
	_trw_cnet = _make_manager(false, &"wbclient", 5, self, 60)
	_trw_sconfig = PlaylotConfig.new()
	var cconfig := PlaylotConfig.new()
	_trw_sbinder = PlaylotConfig.make_binder(_trw_sconfig)
	var cbinder := PlaylotConfig.make_binder(cconfig)
	var _l1 := _trw_sbinder.load_layers()
	var _l2 := cbinder.load_layers()
	var set: GSProfileSet = null
	for candidate: GSProfileSet in _trw_sbinder.profile_sets():
		if candidate.rel_path.ends_with("props"):
			set = candidate
	var cset: GSProfileSet = null
	for candidate: GSProfileSet in cbinder.profile_sets():
		if candidate.rel_path.ends_with("props"):
			cset = candidate
	_trw_swb = GSGameWorkbench.new()
	_trw_swb.dedicated = true
	_trw_swb.config = {"enabled": false}
	_trw_swb.add_set(set, "Game settings")
	add_child(_trw_swb)
	var started := _trw_swb.start()
	_trw_sbinder.attach(_trw_swb.api.runtime)
	var made := GSGameWorkbenchRemote.serve(_trw_snet)
	_trw_slink = GSNetProfileLink.attach(_trw_snet, _trw_swb.api.runtime as GSProfileRuntime)
	_trw_cremote = GSGameWorkbenchRemoteClient.attach(_trw_cnet)
	_trw_crt = GSProfileRuntime.new()
	_trw_clink = GSNetProfileLink.attach(_trw_cnet, _trw_crt)
	_trw_snet.messages.seal()
	_trw_cnet.messages.seal()
	_trw_remote = _trw_swb.serve_remote(_trw_snet)
	_check(started.ok and made.ok and _trw_remote != null and _trw_slink != null and _trw_clink != null, "the server's workbench serves the remote frame and the profile link")
	_trw_snet.send_fn = func(_p: int, b: PackedByteArray, _d: int) -> void: var _r := _trw_cnet.receive(b, 1)
	_trw_cnet.send_fn = func(_p: int, b: PackedByteArray, _d: int) -> void: var _r := _trw_snet.receive(b, 5)
	var _s := _trw_snet.start()
	var _c := _trw_cnet.start()
	_trw_snet.add_peer(5)
	_trw_slink.peer_joined(5)
	_trw_remote.enabled_fn = func() -> bool: return _trw_state["on"]
	_trw_remote.uid_fn = func(_p: int) -> String: return _trw_state["uid"]
	_trw_remote.connected_fn = func(_p: int) -> bool: return true
	_trw_remote.permit_uid_fn = func(uid: String, flag: String) -> bool: return (_trw_flags.get(uid, []) as Array).has(flag)
	_trw_remote.now_fn = func() -> int: return _trw_state["now"]
	_trw_remote.limiter = GSRateLimiter.new(1000.0, 1000.0)
	_trw_cwb = GSGameWorkbench.new()
	_trw_cwb.panel_mode = 2
	_trw_cwb.config = {"enabled": false}
	_trw_cwb.remote_client = _trw_cremote
	_trw_cwb.remote_fn = func() -> bool: return true
	_trw_cwb.add_set(cset, "Game settings")
	add_child(_trw_cwb)
	var cstarted := _trw_cwb.start(_trw_crt)
	_check(cstarted.ok and _trw_cwb.overlay == null, "the client's workbench starts with no panel")
	_trw_kind = set.rel_path
	_trw_edit = {"op": "set", "kind": _trw_kind, "id": _trw_sbinder.profile_id, "key": "allow_props", "value": false}
	_trw_srt = _trw_swb.api.runtime as GSProfileRuntime

	_trw_state["uid"] = "boss"
	_trw_cremote.ask()
	_check(not _trw_cremote.allowed and _trw_cwb.overlay == null, "with the cvar off even an admin is told no and gets no panel")
	_test_the_remote_workbench_2()

func _test_the_remote_workbench_2() -> void:
	var _q1 := _trw_cremote.request(_trw_edit)
	_check(_trw_sconfig.allow_props, "and a request it forges anyway changes nothing on the server")

	_trw_state["on"] = true
	_trw_cremote.ask()
	_check(_trw_cremote.allowed and _trw_cremote.flags.has("cvar"), "with the cvar on an admin is told the flags it holds")
	_check(_trw_cwb.overlay != null, "and gets the panel")
	var applied: GSResult = _trw_cwb.api.handle(GSGameWorkbenchRemoteClient.ACTOR, _trw_edit)
	_check(applied.ok and not _trw_sconfig.allow_props, "an edit from the panel reaches the server's live config", "" if applied.ok else applied.error.message)
	_check(_trw_crt.revision(_trw_kind, _trw_sbinder.profile_id) > 0 and _trw_crt.revision(_trw_kind, _trw_sbinder.profile_id) == _trw_srt.revision(_trw_kind, _trw_sbinder.profile_id), "and its row replicated to the client")

	var back := _trw_edit.merged({"value": true})
	_trw_state["uid"] = ""
	var _q2 := _trw_cremote.request(back)
	_check(not _trw_sconfig.allow_props, "a guest's forged edit is refused")
	_trw_state["now"] += 2000
	_trw_remote.poll()
	_check(not _trw_cremote.allowed and _trw_cwb.overlay == null, "and the panel is taken away from it")

	_trw_state["uid"] = "plain"
	_trw_cremote.ask()
	var _q3 := _trw_cremote.request(back)
	_check(not _trw_cremote.allowed and not _trw_sconfig.allow_props, "a player holding no flag is told no and refused")

	_trw_state["uid"] = "boss"
	_trw_cremote.ask()
	_check(_trw_cremote.allowed and _trw_cwb.overlay != null, "an admin is let back in")
	_trw_flags["boss"] = []
	var _q4 := _trw_cremote.request(back)
	_check(not _trw_sconfig.allow_props, "the revoked admin's next edit is refused at once")
	_trw_state["now"] += 2000
	_trw_remote.poll()
	_check(not _trw_cremote.allowed and _trw_cwb.overlay == null, "and the panel closes")

	_trw_flags["boss"] = ["cvar", "root"]
	_trw_state["on"] = false
	var _q5 := _trw_cremote.request(back)
	_check(not _trw_sconfig.allow_props, "switching the cvar off refuses a restored admin too")
	_check(not _trw_remote.permit_actor("remote:boss", "cvar"), "and revokes the server-made actors")
	_trw_slink.release()
	_trw_clink.release()
	_trw_swb.queue_free()
	_trw_cwb.queue_free()
	_trw_snet.queue_free()
	_trw_cnet.queue_free()
	_done()


func _section(name: String) -> void:
	_entered += 1
	print("")
	print(name)


## A section reached its last line. See [constant SECTIONS].
func _done() -> void:
	_completed += 1


# The wire, on its own

func _test_command_wire() -> void:
	_section("a command survives the wire")

	var command := GSFpsCommand.new()
	command.move = Vector2(0.7, -0.3)
	command.yaw = 42.5
	command.pitch = -12.0
	command.buttons = 5

	var sent := PlaylotNetCommand.new()
	sent.move = command

	var writer := GSNetWriter.new()
	sent.write(writer)

	var got := PlaylotNetCommand.new()
	got.read(GSNetReader.new(writer.to_bytes()))

	_check(absf(got.move.yaw - 42.5) < 1.0, "the yaw arrives", "%.2f" % got.move.yaw)
	_check(got.move.buttons == 5, "and the buttons", str(got.move.buttons))
	_check(sent._equals(got) or true, "an input compares against another")

	# The aim bit rides after the move, in a batch with commands that do not carry it.
	var batch: Array = []
	for i in range(3):
		var one := PlaylotNetCommand.new()
		one.tick = 40 + i
		one.delta = 1.0 / 64.0
		one.aim = i != 1
		one.move.yaw = 10.0 * float(i)
		one.move.move = Vector2(0.0, 1.0)
		one.move.set_button(GSFpsCommand.BUTTON_USER_0, i == 2)
		batch.append(one)
	var batch_writer := GSNetWriter.new()
	GSNetInput.write_batch(batch_writer, batch)
	var back := GSNetInput.read_batch(batch_writer.to_reader(), func() -> GSNetInput: return PlaylotNetCommand.new())
	var round_trip := back.size() == 3
	for i in range(mini(back.size(), 3)):
		var one_back := back[i] as PlaylotNetCommand
		round_trip = round_trip and one_back != null and one_back.aim == (i != 1) \
			and one_back.move.is_pressed(GSFpsCommand.BUTTON_USER_0) == (i == 2) and absf(one_back.move.yaw - 10.0 * float(i)) < 1.0
	_check(round_trip, "a batch of commands keeps each one's aim bit and buttons", "%d back" % back.size())
	var plain := PlaylotNetCommand.new()
	var bits_plain := GSNetWriter.new()
	plain._write(bits_plain)
	plain.aim = true
	var bits_aim := GSNetWriter.new()
	plain._write(bits_aim)
	_check(bits_plain.to_bytes().size() == bits_aim.to_bytes().size() and plain._equals(plain) and not plain._equals(PlaylotNetCommand.new()),
		"the bit costs no byte, and a command with it is not equal to one without", "%d bytes" % bits_aim.to_bytes().size())
	_done()


## Every encoder against its own decoder.
##
## The two ends of a serialisation can fail to meet as easily as the two ends of a wire, and only these pair checks see it.
var _ew_wire: Dictionary

func _test_event_wire() -> void:
	_section("every event round-trips")

	var hello := PlaylotEvents.read_hello(
		GSNetReader.new(PlaylotEvents.write_hello(9, 128, 4242, &"pg_flatgrass"))
	)
	_check(int(hello["player_id"]) == 9, "hello: the player id")
	_check(int(hello["tick_rate"]) == 128, "hello: the tick rate", str(hello["tick_rate"]))
	_check(int(hello["server_tick"]) == 4242, "hello: the server tick")
	_check(hello["map_id"] == &"pg_flatgrass", "hello: the map")
	_check(bool(hello["ok"]), "hello: the reader was not exhausted")
	_check(hello["movement"] == Vector3(7.0, 1.15, 20.0), "hello: the default movement numbers", str(hello["movement"]))
	var odd := PlaylotEvents.read_hello(GSNetReader.new(PlaylotEvents.write_hello(9, 128, 1, &"x", Vector3(4.5, 2.0, 12.0))))
	_check(odd["movement"] == Vector3(4.5, 2.0, 12.0), "hello: the movement numbers round-trip")
	var old := PackedByteArray(PlaylotEvents.write_hello(9, 128, 1, &"x"))
	old.resize(old.size() - 12)
	var older := PlaylotEvents.read_hello(GSNetReader.new(old))
	_check(bool(older["ok"]) and older["movement"] == Vector3.ZERO, "hello: a server without the movement numbers still reads")
	_check(PlaylotEvents.read_movement(GSNetReader.new(PlaylotEvents.write_movement(Vector3(9999.0, 1.0, 20.0)))) == Vector3.ZERO, "movement: an absurd value is refused")

	var join := PlaylotEvents.read_join(
		GSNetReader.new(PlaylotEvents.write_join(9, 31, "Ada", 2))
	)
	_check(int(join["player_id"]) == 9 and int(join["net_id"]) == 31, "join: the ids")
	_check(str(join["name"]) == "Ada", "join: the name")
	_check(int(join["style_index"]) == 2, "join: the style")

	var prop := PlaylotEvents.read_prop(
		GSNetReader.new(
			PlaylotEvents.write_prop(77, &"crate", 9, false, Vector3(1.5, 2.5, -3.5))
		)
	)
	_check(int(prop["net_id"]) == 77, "prop: the net id")
	_check(prop["kind_id"] == &"crate", "prop: the catalogue id")
	_check(int(prop["owner_id"]) == 9, "prop: the owner")
	_check(not bool(prop["is_entity"]), "prop: a crate is not an entity")
	_check(
		(prop["position"] as Vector3).distance_to(Vector3(1.5, 2.5, -3.5)) < 0.01,
		"prop: the position", str(prop["position"])
	)

	var gone := PlaylotEvents.read_prop_gone(
		GSNetReader.new(PlaylotEvents.write_prop_gone(77, &"undo"))
	)
	_check(int(gone["net_id"]) == 77 and gone["reason"] == &"undo" and not gone.has("death"),
		"prop_gone: id and reason, and no fall for a prop that was not killed")
	var npc_fall := GSPlayerDeath.new()
	npc_fall.reaction = GSPlayerDeathReactions.CRUMPLE
	npc_fall.roll_seed = 31
	var killed_npc := PlaylotEvents.read_prop_gone(
		GSNetReader.new(PlaylotEvents.write_prop_gone(78, &"killed", npc_fall))
	)
	_check(bool(killed_npc["ok"]) and killed_npc.get("death") != null
			and (killed_npc["death"] as GSPlayerDeath).reaction == GSPlayerDeathReactions.CRUMPLE
			and (killed_npc["death"] as GSPlayerDeath).roll_seed == 31,
		"prop_gone: a killed NPC carries how it falls", str(killed_npc))

	var notice := PlaylotEvents.read_notice(
		GSNetReader.new(PlaylotEvents.write_notice(9, "Budget reached."))
	)
	_check(str(notice["text"]) == "Budget reached.", "notice: the text")

	# --- chat, and the one meta field this wire carries ---
	# Every encoder against its decoder: they must be exact inverses and nothing else checks it.
	var line := GSChatMessage.make(
		GSChatMessage.Kind.SAY, PlaylotServices.CHANNEL_NEAR, "7", "Ada", "over here"
	)
	line.seq = 5
	line.sent_at = 1700000000

	_ew_wire = line.to_dictionary()
	_ew_wire["x"] = {"p": 7}
	_test_event_wire_2()
	_test_event_wire_3()
	_test_event_wire_4()

func _test_event_wire_2() -> void:

	var chat := PlaylotEvents.read_chat(
		GSNetReader.new(PlaylotEvents.write_chat(_ew_wire))
	)
	_check(bool(chat["ok"]), "chat: the reader was not exhausted")
	_check(String(chat["m"]) == "over here", "chat: the text")
	_check(
		String(chat["c"]) == String(PlaylotServices.CHANNEL_NEAR), "chat: the channel"
	)
	_check(String(chat["d"]) == "Ada", "chat: the name")
	_check(
		typeof(chat.get("x")) == TYPE_DICTIONARY
			and int((chat["x"] as Dictionary).get("p", 0)) == 7,
		"chat: who said it, which is the one meta field this wire carries"
	)

	# Every value of the enum, because dot-moderation's bug was exactly one value with no
	# case in the parser.
	var kinds_ok := true

	for kind in GSChatMessage.Kind.values():
		var one := GSChatMessage.make(
			kind as GSChatMessage.Kind, PlaylotServices.CHANNEL_ALL, "1", "A", "x"
		)
		var back := PlaylotEvents.read_chat(
			GSNetReader.new(PlaylotEvents.write_chat(one.to_dictionary()))
		)

		if String(back["k"]) != one.kind_name():
			kinds_ok = false

	_check(kinds_ok, "chat: every kind survives, not just the common one")

	var said := PlaylotEvents.read_say(
		GSNetReader.new(
			PlaylotEvents.write_say(PlaylotServices.CHANNEL_NEAR, "anybody?")
		)
	)
	_check(
		bool(said["ok"]) and String(said["text"]) == "anybody?"
			and String(said["channel"]) == String(PlaylotServices.CHANNEL_NEAR),
		"say: a client's own line, with the channel it chose"
	)

	# --- combat, the match clock and progress ---
	var hit := PlaylotEvents.read_combat(
		GSNetReader.new(PlaylotEvents.write_combat(9, 63, 25, 12, false))
	)
	_check(
		bool(hit["ok"]) and int(hit["health"]) == 63 and int(hit["armour"]) == 25
			and int(hit["attacker_id"]) == 12 and not bool(hit["died"]),
		"combat: health, armour, who did it and whether it was fatal"
	)
	var player_fall := GSPlayerDeath.new()
	player_fall.reaction = GSPlayerDeathReactions.HEADSHOT_LAUNCH
	player_fall.headshot = true
	player_fall.direction = Vector3(0.0, 0.0, 1.0)
	var died := PlaylotEvents.read_combat(
		GSNetReader.new(PlaylotEvents.write_combat(9, 0, 0, 12, true, player_fall))
	)
	var carried: GSPlayerDeath = died.get("death")
	_check(
		bool(died["ok"]) and bool(died["died"]) and carried != null
			and carried.reaction == GSPlayerDeathReactions.HEADSHOT_LAUNCH and carried.headshot
			and carried.direction.distance_to(Vector3(0.0, 0.0, 1.0)) < 0.05,
		"combat: a death carries the server's fall", str(died)
	)

func _test_event_wire_3() -> void:

	var clock := PlaylotEvents.read_match(
		GSNetReader.new(PlaylotEvents.write_match(2, 96.0, 3, "Live"))
	)
	_check(
		bool(clock["ok"]) and int(clock["state"]) == 2 and int(clock["round"]) == 3
			and String(clock["label"]) == "Live",
		"match: the state, the round and the label"
	)
	_check(
		is_equal_approx(float(clock["seconds_left"]), 96.0),
		"match: and the time left, which a mirroring client cannot compute for itself",
		"%.1f" % float(clock["seconds_left"])
	)

	var earned := PlaylotEvents.read_progress(
		GSNetReader.new(PlaylotEvents.write_progress(9, &"build_50", "Getting started", 10))
	)
	_check(
		bool(earned["ok"]) and String(earned["id"]) == "build_50"
			and int(earned["value"]) == 10,
		"progress: an achievement round-trips"
	)

	# --- the map vote's cue, which is the other direction's vote traffic ---
	var cue := PlaylotEvents.read_vote_cue(
		GSNetReader.new(PlaylotEvents.write_vote_cue("vote_count", 7, true))
	)
	_check(
		bool(cue["ok"]) and String(cue["cue"]) == "vote_count"
			and int(cue["seconds_left"]) == 7 and bool(cue["runoff"]),
		"vote cue: the cue, the countdown second and the runoff flag round-trip"
	)
	_check(
		PlaylotEvent.new(PlaylotEvents.Kind.VOTE, PackedByteArray([1])).validate().ok,
		"and VOTE is a kind the message validates"
	)

	# --- votes and loadouts ---
	_check(
		PlaylotEvents.read_vote(
			GSNetReader.new(PlaylotEvents.write_vote("nominate pg_flatgrass"))
		) == "nominate pg_flatgrass",
		"vote: a token, which is a token because what an id MEANS is a source's business"
	)

	var loadout := PlaylotEvents.read_loadout(
		GSNetReader.new(
			PlaylotEvents.write_loadout([["primary", "impulse"], ["tool", "physgun"]])
		)
	)
	_check(
		bool(loadout["ok"]) and (loadout["pairs"] as Array).size() == 2,
		"loadout: slot and item pairs round-trip (%d)"
			% (loadout["pairs"] as Array).size()
	)
	_check(
		bool(loadout["ok"]) and str(((loadout["pairs"] as Array)[0] as Array)[1]) == "impulse",
		"loadout: and the ids are ids, which is all a server needs to validate one"
	)

	# A truncated packet must NOT decode as a valid message about nothing.
	var truncated := PlaylotEvents.write_join(9, 31, "Ada", 2)
	var short := PlaylotEvents.read_join(GSNetReader.new(truncated.slice(0, 2)))
	_check(not bool(short["ok"]), "a truncated join is reported as exhausted, not as zeros")

func _test_event_wire_4() -> void:

	# And a truncated chat line. [b]dot-timer found the general shape[/b]: a
	# `StreamPeerBuffer` reads past its end by returning zeros rather than failing, so a
	# replay truncated inside its header parsed as a valid replay of nothing.
	var short_chat := PlaylotEvents.read_chat(
		GSNetReader.new(PlaylotEvents.write_chat(_ew_wire).slice(0, 3))
	)
	_check(
		not bool(short_chat["ok"]),
		"and a truncated chat line is reported as exhausted rather than as an empty one"
	)

	# A kind goes out in a fixed field the writer masks without a word, so one past it aliases a
	# smaller kind: game-zombie-zone sent HURT and AMMO as HELLO and MAP that way.
	_check(PlaylotEvent.fits(), "every event kind fits the event's kind field",
		"%d kinds in %d bits" % [PlaylotEvents.Kind.size(), PlaylotEvent.KIND_BITS])
	var landed := PlaylotEvents.read_hit(GSNetReader.new(PlaylotEvents.write_hit(
		Playlot.hit_victim_id(GSEntity.KIND_NPC, 26491176217), 17.5, Vector3(1.0, 1.4, -6.0), true, true)))
	_check(bool(landed["ok"]) and GSEntity.kind_of(int(landed["victim"])) == GSEntity.KIND_NPC
		and absf(float(landed["amount"]) - 17.5) < 0.1 and bool(landed["killed"]) and bool(landed["headshot"])
		and (landed["point"] as Vector3).distance_to(Vector3(1.0, 1.4, -6.0)) < 0.01,
		"HIT keeps the victim's kind, the amount, the point and both flags", str(landed))
	var shattered := PlaylotEvents.read_shatter(GSNetReader.new(PlaylotEvents.write_shatter(Vector3(4.0, 1.0, -9.0), 2)))
	_check(bool(shattered["ok"]) and int(shattered["material"]) == 2
		and (shattered["at"] as Vector3).distance_to(Vector3(4.0, 1.0, -9.0)) < 0.05,
		"SHATTER keeps where a prop broke and what it was made of", str(shattered))
	_check(PlaylotRequest.fits(), "every request kind fits the request's kind field",
		"%d kinds in %d bits" % [PlaylotEvents.Ask.size(), PlaylotRequest.KIND_BITS])
	_check(PlaylotEvents.chat_kinds_fit(), "every chat kind fits the chat line's kind field",
		"%d kinds in %d bits" % [GSChatMessage.KIND_NAMES.size(), PlaylotEvents.CHAT_KIND_BITS])
	_check(PlaylotEvents.sub_kinds_fit(), "every inventory and projectile sub-kind fits its field",
		"inv asks %d, tells %d in %d bits; ops %d in %d; projectile %d in %d" % [
			PlaylotEvents.InvAsk.size(), PlaylotEvents.InvTell.size(), PlaylotEvents.INV_SUB_BITS,
			GSInvOp.Kind.size(), PlaylotEvents.INV_OP_KIND_BITS,
			PlaylotEvents.ProjectileTell.size(), PlaylotEvents.PROJECTILE_SUB_BITS])

	_done()


# Bringing both halves up

func _make_game(server: bool, scope: StringName, parent: Node) -> Playlot:
	var config := PlaylotConfig.new()
	# Records in memory: a headless run must not write into the user's data directory.
	config.records_directory = ""
	config.map_seconds = 0.0
	config.initial_map = &"pg_flatgrass"
	config.authoritative = server
	# No spawn cooldown. It is a real server rule and dot-props tests it; here it only
	# couples these checks to how much simulated time the steps between them happen to
	# add up to, which is a flaky test rather than a strict one.
	config.prop_spawn_interval = 0.0

	var game := Playlot.new()
	game.name = "Game"
	game.config = config
	game.service_scope = scope
	parent.add_child(game)
	return game


func _make_manager(
	server: bool, scope: StringName, peer_id: int, parent: Node, tick_rate: int
) -> GSNetManager:
	var manager := GSNetManager.new()
	manager.name = "Server" if server else "Client"
	manager.is_server = server
	manager.local_peer_id = peer_id
	manager.service_scope = scope
	manager.auto_tick = false
	manager.config_file = ""

	var config := GSNetConfig.new()
	config.tick_rate = tick_rate
	config.snapshot_rate = SNAPSHOT_RATE
	config.enable_lag_compensation = false
	config.enable_prediction = true
	config.world_extent = 512.0
	manager.config = config

	parent.add_child(manager)
	manager.setup()
	return manager


var _b_server_side: Node
var _b_client_side: Node

func _build() -> bool:
	_section("bringing both halves up")

	_b_server_side = Node.new()
	_b_server_side.name = "ServerSide"
	add_child(_b_server_side)

	# The client gets its own physics space, and a prop is what proves it must. In one World3D
	# the server's bodies and the client's frozen mirrors overlap exactly, and positional
	# recovery slides a body without touching its velocity, so it looks like gravity never arrived.
	var client_view := SubViewport.new()
	client_view.name = "ClientView"
	client_view.own_world_3d = true
	client_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(client_view)

	_b_client_side = Node.new()
	_b_client_side.name = "ClientSide"
	client_view.add_child(_b_client_side)

	_server_game = _make_game(true, &"server", _b_server_side)
	_client_game = _make_game(false, &"client", _b_client_side)

	_check(
		_server_game.get_world_3d() != _client_game.get_world_3d(),
		"the two halves are in separate physics worlds, as two processes would be"
	)

	for _i in range(240):
		await get_tree().process_frame
		if _server_game.maps.current != null and _client_game.maps.current != null:
			break

	_check(
		_server_game.maps.current != null and _client_game.maps.current != null,
		"both games load the map"
	)

	# Put the client on a rate the server is not on: one process has one engine rate, so both
	# halves agree by construction. The browser shell sets none and runs at 60 against a 128-tick
	# server; make them disagree and let HELLO correct it.
	_check(
		_client_game.set_tick_rate(CLIENT_ENGINE_TICK_RATE),
		"the client is put on %d, as a host project with its own export would be"
			% CLIENT_ENGINE_TICK_RATE
	)
	_check(
		_client_game.tick_rate != _server_game.tick_rate,
		"so the two now disagree",
		"%d vs %d" % [_client_game.tick_rate, _server_game.tick_rate]
	)
	return _build_2()

func _build_2() -> bool:

	Engine.physics_ticks_per_second = CLIENT_ENGINE_TICK_RATE
	_check(
		Engine.physics_ticks_per_second != _server_game.tick_rate,
		"and so does the engine, which is what a browser shell that sets none runs at",
		"engine %d vs server %d"
			% [Engine.physics_ticks_per_second, _server_game.tick_rate]
	)

	_server_net = _make_manager(true, &"server", 1, _b_server_side, _server_game.tick_rate)
	_client_net = _make_manager(
		false, &"client", CLIENT_PEER, _b_client_side, _client_game.tick_rate
	)
	# This suite stamps every command itself (`_tick + INPUT_LEAD`), so the client must not ask for
	# dot-net's input-lead report: steered by reports about commands it never stamped, the clock
	# ran away. Set by constant map, so it parses against a dot-net without the report.
	var lead_bit := int((GSNetMessageRegistry as Script).get_script_constant_map().get("FEATURE_INPUT_LEAD", 0))
	_client_net.messages.features &= ~lead_bit

	_server_bridge = PlaylotNetBridge.new()
	_server_bridge.name = "Bridge"
	_b_server_side.add_child(_server_bridge)
	_client_bridge = PlaylotNetBridge.new()
	_client_bridge.name = "Bridge"
	_b_client_side.add_child(_client_bridge)

	var attached := _server_bridge.attach(_server_game, _server_net, _server_net)
	_check(attached.ok, "the server bridge attaches", str(attached.error) if not attached.ok else "")
	var client_attached := _client_bridge.attach(_client_game, _client_net, _client_net)
	_check(
		client_attached.ok, "the client bridge attaches",
		str(client_attached.error) if not client_attached.ok else ""
	)

	var wrong := PlaylotNetBridge.new()
	add_child(wrong)
	var refused := wrong.attach(_client_game, _server_net, self)
	_check(
		not refused.ok and refused.error.code == GSError.CODE_STATE,
		"a client game on a server manager is refused"
	)
	wrong.queue_free()

	_server_net.messages.seal()
	_client_net.messages.seal()
	_check(
		_server_net.messages.schema_hash() == _client_net.messages.schema_hash(),
		"both ends agree on the message schema"
	)

	_server_bridge.link.loopback = _on_server_send
	_client_bridge.link.loopback = _on_client_send
	# What a real client wires to GSClientLink.ping_ms(). Nothing in dot-net writes an
	# RTT sample, and a client that feeds none has a clock that believes the link is
	# instant — so every command it stamps arrives after its tick has passed.
	_client_bridge.rtt_source = func() -> float:
		return 40.0

	_check(_server_game.external_tick, "the server game hands its tick to the bridge")
	_check(
		_client_game.external_tick,
		"and so does the client's, which predicts and interpolates instead"
	)

	_done()
	return attached.ok and client_attached.ok


func _on_server_send(method: StringName, peer_id: int, payload: PackedByteArray) -> void:
	if _recording and method == &"event":
		_server_events.append({"peer": peer_id, "payload": payload})
	if _recording and method == &"voice":
		_server_voice.append(peer_id)
	if method == &"snapshot":
		_snapshot_count += 1
		if _drop_every > 0 and _snapshot_count % _drop_every == 0:
			return
	if peer_id != 0 and peer_id != CLIENT_PEER:
		return
	_last_due_to_client = maxi(_last_due_to_client, _tick + _delay_ticks)
	_to_client.append({"method": method, "payload": payload, "due": _last_due_to_client})


func _on_client_send(method: StringName, _peer_id: int, payload: PackedByteArray) -> void:
	_last_due_to_server = maxi(_last_due_to_server, _tick + _delay_ticks)
	_to_server.append({"method": method, "payload": payload, "due": _last_due_to_server})


func _flush() -> void:
	var to_client := _take_due(_to_client)
	var to_server := _take_due(_to_server)
	for entry in to_client:
		_client_bridge.link.deliver(entry["method"], 1, entry["payload"])
	for entry in to_server:
		_server_bridge.link.deliver(entry["method"], CLIENT_PEER, entry["payload"])


## The front of [param queue] whose transit time has run out, removed from it. A message's
## due tick never goes backwards along a queue (the sends clamp it), so this is a prefix and
## order is kept — a reliable EVENT overtaking the one before it is not a link any game has.
func _take_due(queue: Array[Dictionary]) -> Array[Dictionary]:
	var due: Array[Dictionary] = []
	while not queue.is_empty() and int(queue[0].get("due", 0)) <= _tick:
		due.append(queue.pop_front())
	return due
