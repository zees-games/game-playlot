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


## The multi-tool's hand: open and relaxed, palm forward and down so the palm emitter faces the aim, fingers
## loose. [method wrist] grips with it; [method add_poses] teaches it to the arms.
const MULTI_KIND := &"multitool"
const MULTI_HAND := {&"fingers": Vector3(0.0, 0.55, 0.84), &"palm": Vector3(0.0, -0.84, 0.55), &"centre": Vector3(0.0, 0.05, 0.0),
	&"thumb": Vector3(10.0, 14.0, 8.0), &"index": Vector3(12.0, 14.0, 8.0), &"middle": Vector3(16.0, 18.0, 10.0),
	&"ring": Vector3(20.0, 22.0, 12.0), &"pinky": Vector3(24.0, 26.0, 14.0), &"spread": 4.0}


static func add_poses(arms: Node) -> void:
	var poses: Variant = arms.get(&"hand_poses") if arms != null else null
	if poses is Dictionary and not (poses as Dictionary).has(MULTI_KIND):
		(poses as Dictionary)[MULTI_KIND] = {&"firing": MULTI_HAND.duplicate()}


## The arms' grip on the multi-tool's [param anchor]: one hand, its palm on the anchor's origin. Its bounds are a
## sliver round that point, so the elbow-clearance scan does not steer the arm round the band it wears.
static func wrist(anchor: Node3D) -> GSViewGrip:
	var made := GSViewGrip.one_hand(anchor, Vector3.ZERO)
	made.bounds = AABB(Vector3(-0.005, -0.005, -0.005), Vector3(0.01, 0.01, 0.01))
	if "kind" in made:
		made.kind = MULTI_KIND
	return made
