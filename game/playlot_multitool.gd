extends RefCounted
## The multi-tool: the sandbox's physics gun, gravity gun, push, spawn (`swep_spawn.gd`), remover and tool gun
## as ONE worn device with modes. A mode is the id of the tool or weapon it stands for, so the wire
## and the server's `_tool_of` already speak it; this file is the list, its labels and the packing of
## the replicated state. Zee guns are not modes: they stay separate weapons.

## The modes in menu order. The id is the tool (`phys`, `grav`) or the weapon def's id.
const MODES: Array[StringName] = [&"phys", &"grav", &"impulse", &"spawn", &"remover", &"toolgun"]

const LABELS := {
	&"phys": "Physics gun",
	&"grav": "Gravity gun",
	&"impulse": "Push",
	&"spawn": "Spawn",
	&"remover": "Remover",
	&"toolgun": "Tool gun",
}

## The glow of each mode, on the band, the emitter and the beam.
const COLOURS := {
	&"phys": Color(0.25, 0.65, 1.0),
	&"grav": Color(1.0, 0.55, 0.15),
	&"impulse": Color(0.95, 0.9, 0.3),
	&"spawn": Color(0.4, 1.0, 0.5),
	&"remover": Color(1.0, 0.25, 0.25),
	&"toolgun": Color(0.7, 0.45, 1.0),
}

## Default seconds R is held before the selector opens. The setting `multitool_hold_seconds`
## overrides it; 0 opens at once.
const HOLD_SECONDS := 0.25

const _RAISED_BIT := 1
const _MODE_SHIFT := 1
const _MODE_MASK := 0x3F
const _FIRE_SHIFT := 7
const _FIRE_MASK := 0xF


## What spawn mode puts down: `kind:id`, kind one of [constant PICK_KINDS]. A bare id is a prop.
const PICK_KINDS: Array[String] = ["prop", "weapon", "addon", "build"]


static func pick(kind: String, id: String) -> StringName:
	return StringName("%s:%s" % [kind, id])


## [kind, id] of a pick; anything not led by a [constant PICK_KINDS] kind is a bare prop id
## (a pack prop's own id may hold a colon).
static func pick_parts(picked: StringName) -> PackedStringArray:
	var text := String(picked)
	var colon := text.find(":")
	if colon < 0 or not PICK_KINDS.has(text.substr(0, colon)):
		return PackedStringArray(["prop", text])
	return PackedStringArray([text.substr(0, colon), text.substr(colon + 1)])


static func has_mode(id: StringName) -> bool:
	return MODES.has(id)


static func index_of(id: StringName) -> int:
	return MODES.find(id)


static func label(id: StringName) -> String:
	return String(LABELS.get(id, String(id)))


static func colour(id: StringName) -> Color:
	return COLOURS.get(id, Color(0.6, 0.8, 1.0)) as Color


## The modes this game has: a mode whose weapon def a game left out is not offered.
static func available(game: Object) -> Array[StringName]:
	var out: Array[StringName] = []
	for id in MODES:
		if id == &"phys" or id == &"grav" or game == null or game.call("weapon_def", id) != null:
			out.append(id)
	return out


## Raised, mode index (-1 = not wielding) and the fire counter, into the replicated integer.
static func pack(raised: bool, mode_index: int, fire: int) -> int:
	return (_RAISED_BIT if raised else 0) \
		| (((mode_index + 1) & _MODE_MASK) << _MODE_SHIFT) \
		| ((fire & _FIRE_MASK) << _FIRE_SHIFT)


static func unpack(packed: int) -> Dictionary:
	return {
		"raised": (packed & _RAISED_BIT) != 0,
		"mode_index": ((packed >> _MODE_SHIFT) & _MODE_MASK) - 1,
		"fire": (packed >> _FIRE_SHIFT) & _FIRE_MASK,
	}
