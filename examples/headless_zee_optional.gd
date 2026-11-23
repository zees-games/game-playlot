extends GSGameCheckSuite

const PlaylotZee := preload("../game/playlot_zee.gd")
const PlaylotWeapons := preload("../game/playlot_weapons.gd")
const PlaylotShotSound := preload("../game/client/playlot_shot_sound.gd")
const PlaylotHud := preload("../game/playlot_hud.gd")

## zee-gs-weapons is optional: Playlot's own tools are the default and Zee is a Workshop extra.
##
## Both halves in one run. Absent ([member PlaylotZee.force_absent], which every Zee use in
## game/ passes through): no Zee weapons, no rigs, no views, the HUD and the shot sound quiet,
## the same net schema. Present (the linked addon): the pack's weapons arm and fire. The pack's
## derived requirements must not name zee_weapons, or the solo shell refuses to start the game
## ("This game needs zee-weapons") for everybody who has not subscribed to it.
##
## [codeblock]
## ./game.sh test headless_zee_optional
## [/codeblock]

const CHECKS := 24
const SECTIONS := 3


func _ready() -> void:
	GSLog.set_level(GSLog.Level.ERROR)
	_run.call_deferred()


func _run() -> void:
	print("game-playlot: zee-gs-weapons optional")
	var entered := 0
	var finished := 0

	entered += 1
	_derive()
	finished += 1

	entered += 1
	var present_specs := _present()
	finished += 1

	entered += 1
	_absent(present_specs)
	finished += 1

	PlaylotZee.reset()
	_report_sections(entered, finished, SECTIONS, CHECKS)


func _derive() -> void:
	var derived := GSAddonApi.derive("res://")
	_check(not derived.has("zee_weapons"), "the pack's derived requirements leave zee_weapons out", str(derived.keys()))
	var floors := FileAccess.get_file_as_string("res://" + GSAddonApi.FLOOR_FILE)
	_check(floors != "" and not floors.contains("zee_weapons"), "and so does %s" % GSAddonApi.FLOOR_FILE)


## The linked addon: the guarded loads reach the real thing. Returns zee's own net fields.
func _present() -> Array:
	PlaylotZee.reset()
	_check(PlaylotZee.available(), "zee is found by path when it is installed")
	var defs := PlaylotZee.defs()
	_check(not defs.is_empty(), "its weapons join the menu (%d)" % defs.size())
	var smg := PlaylotZee.find_def(&"zee_smg")
	_check(smg != null and PlaylotZee.npc_can_use(smg), "an NPC may hold the zee smg")

	var body := Node3D.new()
	body.name = "Holder"
	add_child(body)
	var rig := PlaylotZee.arm(body, smg, PlaylotZee.ROLE_SERVER, true, 64, 0) if smg != null else null
	_check(PlaylotZee.is_rig(rig) and PlaylotZee.arsenal_of(rig) != null, "a server rig arms with it")
	var command := PlaylotZee.command_for(0, 0.0, 0.0, PlaylotZee.slot_of(rig))
	_check(PlaylotZee.simulate(rig, command, 1) != null, "and ticks through the facade")
	var view := PlaylotZee.new_view_model()
	_check(PlaylotZee.rig_class() != &"" and view is Node3D, "the view model is zee's")
	if view != null:
		view.free()
	body.free()

	var specs: Variant = PlaylotZee.call_static("net/zee_weapon_net.gd", &"all_specs", [], [])
	return specs if specs is Array else []


## Zee forced away, as on a client that never subscribed: everything still runs.
func _absent(present_specs: Array) -> void:
	PlaylotZee.reset()
	PlaylotZee.force_absent = true
	_check(not PlaylotZee.available() and PlaylotZee.defs().is_empty(), "without zee there are no zee weapons")
	_check(PlaylotZee.find_def(&"zee_smg") == null and not PlaylotZee.npc_can_use(null), "and an NPC preset's zee gun is no gun")

	var built := PlaylotWeapons.built_in()
	var first: StringName = &""
	for def in built:
		if def.id != &"launcher":
			first = def.id
			break
	_check(not built.is_empty() and first != &"", "Playlot's own tools are there, %s first" % first)

	var body := Node3D.new()
	body.name = "Unarmed"
	add_child(body)
	_check(PlaylotZee.arm(body, null, PlaylotZee.ROLE_SERVER, true, 64, 0) == null and PlaylotZee.rig_of(body) == null,
		"arming gives no rig")
	_check(PlaylotZee.simulate(null, PlaylotZee.command_for(1, 0.0, 0.0, 0), 1) == null, "and a tick with no rig fires nothing")
	_check(PlaylotZee.arsenal_of(null) == null and PlaylotZee.current_def(null) == null, "nor holds anything")
	body.free()

	_check(PlaylotZee.new_view_model() == null and PlaylotZee.new_world_model() == null, "no view or world model")
	_check(PlaylotZee.new_scope_overlay() == null and PlaylotZee.load_ads_rules() == null, "no scope and no ads rules")
	_check(PlaylotZee.weapon_table().is_empty() and PlaylotZee.art_for(&"smg") == null, "no art")
	_check(PlaylotZee.shot_fx_warm().is_empty() and PlaylotZee.rig_class() == &"", "nothing to prewarm")

	var hud := PlaylotHud.new()
	add_child(hud)
	hud.show_weapon(null)
	hud.follow_hands(null)
	hud.set_aim(0.5, true)
	_check(hud.scope == null and hud.ammo.count_text() == "", "the HUD runs with no scope and no counter")
	hud.free()

	var sound := PlaylotShotSound.new()
	add_child(sound)
	_check(not sound.warm() and not sound.is_ready(), "the layered shot sound stays off")
	sound.free()

	var specs := PlaylotZee.net_specs()
	_check(specs.size() == present_specs.size() and _same_specs(specs, present_specs),
		"the net schema is zee's own, bit for bit, so a mixed server and client agree", str(specs.size()))
	var source := Node.new()
	_check(int(PlaylotZee.net_apply(source, null, 5)["seq"]) == 5, "a watcher with no zee keeps its fire counter")
	source.free()
	var carrier := _Carrier.new()
	carrier.net_fire_seq = 9
	_check(int(PlaylotZee.net_apply(carrier, null, 3)["seq"]) == 9, "and follows the server's")
	PlaylotZee.net_pull(null, carrier)
	_check(carrier.net_fire_seq == 9, "pulling from no rig leaves the fields")
	PlaylotZee.reset()


func _same_specs(a: Array, b: Array) -> bool:
	for i in a.size():
		var x: Dictionary = a[i]
		var y: Dictionary = b[i]
		if StringName(x["property"]) != StringName(y["property"]) or str(x["type"]) != str(y["type"]) \
				or int(x["bits"]) != int(y["bits"]):
			return false
	return true


class _Carrier:
	extends RefCounted
	var net_fire_seq: int = 0
