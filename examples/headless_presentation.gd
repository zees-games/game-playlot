extends "res://examples/headless_presentation_chat_and_touch.gd"


## The five addons this game gained at once: settings, randomness, audio, effects and a
## console — plus the generated map, the carried inventory, and the party.
##
## [codeblock]
## godot --headless --path . res://examples/headless_presentation.tscn
## [/codeblock]
##
## [b]This is the only game in the family that holds all eight[/b], and the checks worth
## having are the ones about them meeting: one seed behind the map and the audio, one list
## behind the spawn menu and the backpack, and a generated map that is refused rather than
## shipped when nobody could cross it.
##
## Exits non-zero on any failure.


const CHECKS := 182
const SECTIONS := 20

## The player's own settings directory as it was before this run: every file's name,
## modification time and digest. Checked at the end; see
## [method PlaylotPresentation.use_scratch_settings].
var _player_files_were: String = ""


func _ready() -> void:
	# Before anything builds a presentation layer: the Escape menu section drags the volume
	# to 0.15 and that used to land in this machine's real settings folder, so
	# the next real session started nearly silent. Everything goes to a scratch directory
	# emptied first, never the player's.
	_player_files_were = _player_files_stamp()
	var _scratch := PlaylotPresentation.use_scratch_settings("headless_presentation")
	GSLog.set_level(
		GSLog.Level.DEBUG if "--verbose" in OS.get_cmdline_user_args()
		else GSLog.Level.ERROR
	)
	_run.call_deferred()


func _run() -> void:
	print("game-playlot: the presentation layer")

	_test_one_seed()
	_test_generated_map_is_walkable()
	_test_generation_refuses_rather_than_ships()
	_test_the_backpack_is_the_prop_catalogue()
	_test_carrying_is_a_refusal()
	_test_sounds_and_effects()
	_test_effects_draw()
	_test_breaks_throw_pieces()
	await _test_blood()
	_test_console()
	_test_party_does_not_migrate()
	await _test_party_over_http()
	await _test_escape_menu()
	_test_touch_buttons()
	_test_chat_box()
	await _test_glance_pieces()

	_test_every_sound_has_a_voice()
	_test_ambience_is_quiet_and_obeys_settings()
	_test_the_vote_is_heard()
	_test_texture_quality_reaches_the_map_art()

	# A settings manager writes on a debounce, and a freed one writes in `_exit_tree`:
	# the Escape menu section's presentation is queued for freeing and only reaches the
	# disk at the end of this frame. Without these the check below looked before the
	# write and passed on the code that wrote the player's file.
	await get_tree().process_frame
	await get_tree().process_frame
	print("")
	_check(
		_player_files_stamp() == _player_files_were,
		"the player's own settings files were not touched",
		PlaylotPresentation.PLAYER_SETTINGS
	)
	_report_sections(_entered, _completed, SECTIONS, CHECKS)


## Every file in the player's own settings directory, as name, modification time and MD5,
## or "" when there is no directory. A digest as well as a time, because a write within
## the same second as the stamp leaves the time where it was.
static func _player_files_stamp() -> String:
	var dir := ProjectSettings.globalize_path(PlaylotPresentation.PLAYER_SETTINGS)
	if not DirAccess.dir_exists_absolute(dir):
		return ""
	var lines := PackedStringArray()
	for f in DirAccess.get_files_at(dir):
		var path := dir.path_join(f)
		lines.append("%s %d %s" % [f, FileAccess.get_modified_time(path), FileAccess.get_md5(path)])
	return "\n".join(lines)


func _test_escape_menu() -> void:
	_section("Escape reaches a setting, which it could not before")
	var p := PlaylotPresentation.new()
	p.name = "MenuP"
	add_child(p)
	if not _check(p.setup().ok, "a presentation layer to read the settings from"):
		_done()
		return
	# This section writes through the real file store (the menu's Apply is what it is
	# about), so the store must be the scratch one `_ready` chose, not the player's.
	_check(
		PlaylotPresentation.settings_directory.begins_with("user://scratch/"),
		"its settings are a scratch document, not the player's",
		PlaylotPresentation.settings_directory
	)
	var stack := GSScreenStack.new()
	stack.name = "Stack"
	stack.register_service = false
	stack.manage_mouse = false
	add_child(stack)
	stack.setup()

	var pause := GSPauseScreen.new()
	pause.name = "Pause"
	_check(
		pause.build(PackedStringArray(["Resume", "Settings", "Servers", "Leave"])).ok,
		"a pause menu builds"
	)
	stack.register(pause)

	var screen := GSSettingsScreen.new()
	screen.name = "Settings"
	_check(screen.build(p.settings).ok, "and a settings screen onto the real settings")
	stack.register(screen)

	var gm := GSMenu.new()
	gm.settings = p.settings
	gm.open_on_escape = false
	gm.manage_pointer = false
	add_child(gm)
	var gm_set: GSResult = gm.setup()
	PlaylotClient.add_general_rows(gm)
	var gm_image := gm.page(&"video").find_section(&"image")
	var gm_gore: GSMenuRow = gm_image.find_row(&"gore") if gm_image != null else null
	_check(gm_gore != null and gm_gore.row_id() == &"gore" and p.settings.schema.has(&"gore"),
		"the Video page's Image section has a Blood splatters row on the gore setting",
		"%s %s %s" % [gm_set.ok, gm_image, gm_gore])

	stack.push(&"pause")
	await get_tree().process_frame
	await get_tree().process_frame

	# THAT THE PUSH LANDED, which is the check this section shipped without.
	#
	# `GSScreen`'s default id is the NODE NAME, so a screen called `Pause` registered as
	# `&"Pause"` and `push(&"pause")` answered "no such screen" -- reported, not fatal, so
	# this game's pause menu never opened at all. Every check below passed anyway: a
	# REGISTERED screen is sized and focusable whether or not it is on screen. A rendered
	# frame in gs-ui is what found it, and this is the assertion that would have.
	_check(stack.top_id() == &"pause", "the menu OPENS, rather than registering under its node name")
	_check(pause.visible, "so it is actually on screen")

	# The one thing an assertion reaches about a Control, and this family has shipped a
	# 0 x 0 one twice.
	_check(pause.size.x > 0.0 and pause.size.y > 0.0, "the menu has a size")
	_check(
		pause.get_node_or_null(pause.initial_focus) != null,
		"and something focused, or it cannot be used with a gamepad at all"
	)
	_check(pause.button(&"settings") != null, "with a way to reach the settings")

	stack.push(&"settings")
	await get_tree().process_frame

	# The check this section exists for: `to_config()` is a SNAPSHOT and
	# `absorb_config()` is the way back. A screen that called only the panel's apply would
	# report success and change nothing, for ever, and every check above passes either way.
	p.settings.set_value(&"master_volume", 0.9)
	screen._on_push()
	screen.panel._edited("master_volume", 0.15)
	screen.apply()
	_check(
		is_equal_approx(p.settings.get_float(&"master_volume"), 0.15),
		"Apply reaches the settings manager rather than the snapshot it was bound to"
	)
	_check(
		is_equal_approx(p.audio.mixer.master, 0.15),
		"and carries on to the mixer, which is what a player actually hears"
	)

	stack.clear()
	stack.queue_free()
	p.queue_free()
	_done()

## The ammo counter, hit marker and damage numbers are gs-ui's glance pieces, fed this game's numbers.
func _test_glance_pieces() -> void:
	_section("What is in hand, and what a shot did")
	var p := _make()
	var hud := PlaylotHud.new()
	hud.name = "GlanceHud"
	add_child(hud)
	# A real rig, holding the first zee weapon with a magazine, on a stand-in body.
	var body := Node3D.new()
	body.name = "Holder"
	add_child(body)
	var rig: ZeeWeaponRig = null
	for def in PlaylotZee.defs():
		var weapon := PlaylotZee.catalogue().get_def(PlaylotZee.zee_id(def)) if PlaylotZee.is_zee(def) else null
		if weapon != null and weapon.magazine > 0 and weapon.ammo_type != &"":
			rig = PlaylotZee.arm(body, def, ZeeWeaponRig.Role.SERVER, true, 64, 0)
			break
	_check(rig != null, "a zee weapon is armed for the counter to read")
	var stock_problems := GSWeaponSound.check_stock()
	_check(stock_problems.is_empty(), "every weapon class resolves a non-silent, unclipped stock voice (%s)" % ", ".join(stock_problems))
	if rig == null:
		hud.queue_free()
		body.queue_free()
		_done()
		return
	var slot := rig.arsenal.current()
	slot.magazine = 3
	hud.show_weapon(rig)
	var reserve := rig.arsenal.ammo().count(slot.def.ammo_type)
	_check(
		hud.ammo.count_text() == "3 | %d" % reserve and hud.ammo.low,
		"the counter shows the magazine and the reserve, low at a quarter",
		"'%s' low=%s for %d of %d" % [hud.ammo.count_text(), str(hud.ammo.low), slot.magazine, slot.def.magazine]
	)
	hud.show_weapon(null)
	_check(hud.ammo.count_text() == "" and not hud.ammo.footprint().has_area(),
		"and nothing at all with a toy or empty hands", hud.ammo.count_text())
	hud.show_weapon(rig)

	hud.confirm_hit(Playlot.hit_victim_id(GSEntity.KIND_NPC, 41), 26.0, Vector3(0, 1, -5), true, false)
	_check(
		hud.hit_marker.alpha() > 0.0 and hud.hit_marker.kill and Array(hud.damage_numbers.texts()).has("26"),
		"a confirmed hit flashes the marker and puts the number up",
		"%s %s" % [str(hud.hit_marker.describe()), str(hud.damage_numbers.texts())]
	)

	# Out of the chat box's way: the narrowest frame a client shell draws.
	await get_tree().process_frame
	var window := p.chat_window
	var plate := hud.ammo.get_global_transform() * hud.ammo.footprint()
	var box := window.get_global_rect()
	_check(not plate.intersects(box), "the counter does not meet the chat box",
		"counter %s, box %s" % [str(plate), str(box)])
	var narrow := 854.0
	var plate_w := hud.ammo.footprint().size.x
	_check(
		window.margin_left + window.width + 8.0 <= narrow + hud.ammo.offset_right - plate_w,
		"nor at 854 wide, the smallest frame",
		"box to %.0f, counter from %.0f" % [window.margin_left + window.width, narrow + hud.ammo.offset_right - plate_w]
	)

	# A ballot where a shell draws one, top right, leaves it alone; one over it dims it.
	var ballot := GSBallotPanel.new()
	ballot.name = "GlanceBallot"
	ballot.panel_width = 360.0
	add_child(ballot)
	ballot.show_state({"open": true, "title": "Next map", "command": "nominate", "seconds": 30,
		"options": [{"id": "a", "label": "Lobby", "votes": 0}, {"id": "b", "label": "Canyon", "votes": 0}],
		"voters": {}})
	var view := get_viewport().get_visible_rect().size
	ballot.position = Vector2(view.x - 360.0 - 24.0, 120.0)
	await get_tree().process_frame
	hud.ammo.refresh_cover()
	_check(not hud.ammo.covered, "a ballot top right leaves the counter alone",
		"ballot %s, counter %s" % [str(ballot.get_global_rect()), str(plate)])
	ballot.position = Vector2(view.x - 360.0 - 24.0, view.y - 140.0)
	await get_tree().process_frame
	hud.ammo.refresh_cover()
	_check(hud.ammo.covered and hud.ammo.self_modulate.a < 1.0, "and one over it dims it",
		"ballot %s" % str(ballot.get_global_rect()))

	_check_camera_motion(p)
	_check_ui_floor()

	ballot.queue_free()
	hud.queue_free()
	body.queue_free()
	_done()


## The camera motion settings reach the player they are bound to, live.
func _check_camera_motion(p: PlaylotPresentation) -> void:
	var stub := GDScript.new()
	stub.source_code = "extends Node\nvar got: Array = []\nfunc set_camera_motion_scales(a: float, b: float, c: float) -> void:\n\tgot = [a, b, c]\n"
	var _compiled := stub.reload()
	var holder := Node.new()
	holder.set_script(stub)
	add_child(holder)
	p.bind_camera_motion(holder)
	var bound: Array = holder.get(&"got")
	p.settings.set_value(&"camera_strafe_roll", 0.0)
	p.settings.set_value(&"camera_speed_fov", 1.5)
	var moved: Array = holder.get(&"got")
	_check(bound == [1.0, 1.0, 1.0] and moved == [1.0, 0.0, 1.5],
		"the camera motion settings reach the camera: bound at the picks, then each slider on its own",
		"%s then %s" % [str(bound), str(moved)])
	_check(p.settings.schema.find(&"camera_landing_dip") != null
		and p.settings.schema.find(&"camera_landing_dip").scope == GSSettingsDef.Scope.ACCOUNT,
		"and they belong to the person, not the machine")
	holder.queue_free()


## A pack naming these classes does not parse on a shell whose gs-ui predates them, so the
## requires.json gs-ci derives must ask for gs-ui 4, and nothing may lower it.
## The floor file exists to name the game addons solo play fetches; it must not lower gs-ui.
func _check_ui_floor() -> void:
	var asks := GSAddonApi.derive()
	var floor_path := "res://" + GSAddonApi.FLOOR_FILE
	var floors := {}
	if FileAccess.file_exists(floor_path):
		var parsed := GSAddonApi.parse(FileAccess.get_file_as_string(floor_path), GSAddonApi.FLOOR_FILE)
		floors = {"gs_ui": 0}
		if parsed.ok:
			floors = parsed.value
	_check(
		int(GSAddonApi.apply_floors(asks, floors).get("gs_ui", 0)) >= 4,
		"the pack asks a shell for gs-ui level 4, the glance pieces",
		str(asks.get("gs_ui"))
	)


## `[p2p-await-games]`: a party over the HTTP rendezvous, host and join, each awaited end to end through
## `PlaylotParty`, `GSP2PSession` and `GSP2PSignallerHttp`. The caller's answer must be the stub's, arriving at
## least [member RendezvousStub.delay] frames after the call: a link that dropped its `await` fails here.
func _test_party_over_http() -> void:
	_section("A party that meets over HTTP waits for the answer")

	var stub := RendezvousStub.new()
	stub.name = "Rendezvous"
	add_child(stub)
	var listening := stub.start()
	_check(listening, "a stand-in rendezvous listens on a local port", str(stub.port))

	if not listening:
		stub.queue_free()
		_done()
		return

	var url := "http://127.0.0.1:%d/p2p" % stub.port
	var ada := PlaylotParty.new()
	ada.name = "PartyAda"
	ada.signalling_url = url
	add_child(ada)
	var bob := PlaylotParty.new()
	bob.name = "PartyBob"
	bob.signalling_url = url
	add_child(bob)

	_check(
		ada.setup().ok and bob.setup().ok
			and ada.session.signaller is GSP2PSignallerHttp
			and bob.session.signaller is GSP2PSignallerHttp,
		"two parties set up with a URL, and both meet over HTTP rather than the loopback"
	)

	var opened: Array[String] = []
	ada.open.connect(func(code: String) -> void: opened.append(code))

	var before := Engine.get_process_frames()
	var hosted: GSResult = await ada.host("Ada")
	var took := Engine.get_process_frames() - before
	var code := str(hosted.value) if hosted != null and hosted.ok else ""

	_check(
		hosted != null and hosted.ok and GSP2PLobby.is_code_shaped(code, ada.session.config.code_length),
		"host() hands back a join code",
		str(hosted.error.message) if hosted != null and not hosted.ok else "null"
	)
	_check(took >= stub.delay,
		"only once the rendezvous has answered: %d frames, the stub waits %d" % [took, stub.delay])
	_check(
		stub.seen.size() >= 1 and stub.seen[0]["route"] == "host"
			and str((stub.seen[0]["body"] as Dictionary).get("code", "")) == code
			and str(((stub.seen[0]["body"] as Dictionary).get("info", {}) as Dictionary).get("name", "")) == "Ada",
		"and it is the code the rendezvous was told, under the host's name",
		str(stub.seen)
	)
	_check(ada.active() and ada.session.is_host() and opened == [code],
		"the party is open, hosted, and says so once",
		"state %s, opened %s" % [ada.session.state(), str(opened)])

	before = Engine.get_process_frames()
	var joined: GSResult = await bob.join(code.to_lower(), "Bob")
	took = Engine.get_process_frames() - before

	_check(joined != null and joined.ok and took >= stub.delay,
		"join() waits for the rendezvous too (%d frames) and succeeds" % took,
		str(joined.error.message) if joined != null and not joined.ok else "null")
	_check(
		stub.seen.size() >= 2 and stub.seen[1]["route"] == "join"
			and str((stub.seen[1]["body"] as Dictionary).get("code", "")) == code,
		"under the code as the host has it, not as it was typed",
		str(stub.seen)
	)
	_check(
		bob.session.lobby.has(ada.session.local_id) and not bob.session.is_host(),
		"and the joiner learns who is already there from the answer, and does not elect itself",
		str(bob.session.lobby.member_ids())
	)

	# A refusal arrives as a failure the caller can read, not as null and not as success.
	bob.leave()
	var carol := PlaylotParty.new()
	carol.name = "PartyCarol"
	carol.signalling_url = url
	add_child(carol)
	var _set := carol.setup()
	stub.refuse = 403
	var refused: GSResult = await carol.host("Carol")
	_check(refused != null and not refused.ok and not carol.active(),
		"and a rendezvous that refuses leaves the party closed with a reason",
		"null" if refused == null else ("ok" if refused.ok else refused.error.message))

	ada.leave()
	for node: Node in [ada, bob, carol, stub]:
		node.queue_free()
	_done()


func _test_texture_quality_reaches_the_map_art() -> void:
	_section("The video setting's texture quality caps the map art")
	var p := _make()
	GSMapTextureTier.current_quality = -1
	p.settings.set_value(&"texture_quality", 3)
	var q: int = int(p.settings.get_value(&"texture_quality"))
	GSMapTextureTier.follow(p.settings)
	_check(GSMapTextureTier.current_quality == int(q), "the presentation's settings drive the tier", str(GSMapTextureTier.current_quality))
	p.settings.set_value(&"texture_quality", 0)
	var s := GSMapSurfaces.new()
	var applied: Dictionary = GSMapTextureTier.apply_current(s)
	_check(GSMapTextureTier.current_quality == 0 and s.max_texture_size == 512 and not applied.is_empty(), "low texture quality caps the map's surfaces at 512", str(s.max_texture_size))
	p.settings.set_value(&"texture_quality", 3)
	var u := GSMapSurfaces.new()
	GSMapTextureTier.apply_current(u)
	_check(u.max_texture_size == 0, "ultra leaves them unlimited", str(u.max_texture_size))
	GSMapTextureTier.current_quality = -1
	p.queue_free()
	_done()
