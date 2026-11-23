extends "playlot_prop_net.gd"

## An armed NPC: everything a prop replicates, and the weapon in its hands.
##
## [b]Which weapon, and a fire counter — the same four fields a player's weapon sends.[/b]
## A watcher's world model kicks once per snapshot in which the counter moved, which is how
## somebody else's gun is seen to fire (`ZeeWeaponNet.apply` says why a counter and not an
## event per shot). An NPC is "somebody else" to every client, so it is drawn exactly as a
## remote player's weapon is, from the same fields.
##
## The weapon is drawn in a hands node this makes on the mirror: a client copy has no
## script — the AI runs on the server only — so nothing else there would make one.

const NpcHands := preload("../entities/npc_hands.gd")
const PlaylotZee := preload("../playlot_zee.gd")

## The game's weapon id in its hands (`zee_smg`), or empty.
var net_weapon: String = ""

var net_fire_seq: int = 0
var net_fire_kind: int = 0
var net_reloading: bool = false
var net_switching: bool = false

var _seen_fire_seq: int = 0
var _shown_weapon: String = ""
var _hands: Node3D = null
var _model: Node3D = null


func _register_net_vars() -> void:
	super()
	replicate(&"net_weapon", GSNetVar.Type.STRING)

	for spec in PlaylotZee.net_specs():
		var name: StringName = spec["property"]

		# Only the fields a watcher's world model reads. The magazine and the reserve are the
		# holder's own business, and an NPC is nobody's.
		if not [&"net_fire_seq", &"net_fire_kind", &"net_reloading", &"net_switching"].has(name):
			continue

		var field := replicate(name, GSNetVar.Type[spec["type"]])

		if int(spec["bits"]) > 0:
			field.bits(int(spec["bits"]))


func pull() -> void:
	super()

	if prop == null or not is_instance_valid(prop):
		return

	var held: Variant = prop.get("weapon_id")
	net_weapon = String(held) if held != null else ""

	var rig: Variant = prop.get("zee_rig")

	PlaylotZee.net_pull(rig, self)


func _net_state_applied(tick: int) -> void:
	super(tick)

	if identity != null and identity.is_authoritative:
		return

	_show_weapon()

	if _model != null:
		var answer := PlaylotZee.net_apply(self, _model, _seen_fire_seq)
		_seen_fire_seq = int(answer["seq"])


func _show_weapon() -> void:
	if net_weapon == _shown_weapon or prop == null:
		return

	_shown_weapon = net_weapon

	if _model != null:
		_model.queue_free()
		_model = null

	if net_weapon == "":
		return

	if _hands == null:
		_hands = NpcHands.new()
		_hands.name = "Hands"
		prop.add_child(_hands)
		_hands.position = Vector3(0.35, 0.25, -0.35)

	# Without the zee_weapons addon there is no art and no model: the NPC is seen unarmed.
	var art := PlaylotZee.Art.art_for(PlaylotZee.zee_id(PlaylotZee.find_def(StringName(net_weapon))))

	if art == null:
		return

	_model = PlaylotZee.Art.new_world_model()

	if _model == null:
		return

	if not bool(_model.call(&"attach_to", _hands)):
		_model.free()
		_model = null
		return

	var _equipped: Variant = _model.call(&"equip", art)
