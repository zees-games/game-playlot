extends RefCounted
## The multi-tool: the sandbox's physics gun, gravity gun, push, spawn launcher, remover and tool gun
## as ONE worn device with modes. A mode is the id of the tool or weapon it stands for, so the wire
## and the server's `_tool_of` already speak it; this file is the list, its labels and the packing of
## the replicated state. Zee guns are not modes: they stay separate weapons.

## The modes in menu order. The id is the tool (`phys`, `grav`) or the weapon def's id.
const MODES: Array[StringName] = [&"phys", &"grav", &"impulse", &"launcher", &"remover", &"toolgun"]

const LABELS := {
	&"phys": "Physics gun",
	&"grav": "Gravity gun",
	&"impulse": "Push",
	&"launcher": "Spawn",
	&"remover": "Remover",
	&"toolgun": "Tool gun",
}

## The glow of each mode, on the band, the emitter and the beam.
const COLOURS := {
	&"phys": Color(0.25, 0.65, 1.0),
	&"grav": Color(1.0, 0.55, 0.15),
	&"impulse": Color(0.95, 0.9, 0.3),
	&"launcher": Color(0.4, 1.0, 0.5),
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
