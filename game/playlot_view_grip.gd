extends RefCounted

## Where the first-person hands go on a zee weapon: ZeeViewModel measures the grip and fore-end
## from the weapon's own bounds, this only maps its pose to one hand or two.

const NEEDS_LEVEL := 8
## Poses held with the firing hand alone.
const ONE_HAND: Array[StringName] = [&"melee", &"thrown", &"fists"]
## A zee pose to the gs-player-char hand pose kind (GSViewHandPoses) the fingers close in; a pose missing here
## is held as a rifle. Older gs-player-char builds have no grip kind and keep their one shared pose.
const POSE_KINDS := {&"rifle": &"rifle", &"pistol": &"pistol", &"heavy": &"launcher", &"melee": &"knife",
	&"thrown": &"grenade", &"fists": &"fists"}


static func available() -> bool:
	return GSAddonApi.build_level("gs_player_char") >= NEEDS_LEVEL


## The grip for a hands_reached call, reusing [param old] while the weapon and hand count hold.
static func update(old: GSViewGrip, anchor: Node3D, grip: Vector3, fore: Vector3, pose: StringName) -> GSViewGrip:
	var one := pose in ONE_HAND
	var made := old
	if made == null or made.anchor != anchor or made.is_two_hand() == one:
		made = GSViewGrip.one_hand(anchor, grip) if one else GSViewGrip.two_hand(anchor, grip, fore)
	made.grip = grip
	if not one:
		made.support = fore
	if "kind" in made:
		made.kind = POSE_KINDS.get(pose, &"rifle")
	return made
