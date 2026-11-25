extends RefCounted
## Where the multi-tool's bracelet sits on a person: the right wrist (the hand that wears it in first person), found on whatever rig the avatar has, along the forearm and sized to it.
## [b]Tolerant, then shared, then loud.[/b] The family's figure hands out a hand mount ([code]GSHumanoidFigure.attachment[/code]); a rig whose bones are named another way (a library avatar, a `mixamorig:` rig, `lowerarm_l`) still gets the bracelet, on the bone this finds by reading the names.
## A rig with nothing that looks like an arm is drawn at the figure's own fallback spot with an error in the log, never silently.

const CHANNEL := "playlot.multi.mount"

## Words that make a bone a finger, not a wrist.
const FINGERS: Array[String] = ["thumb", "index", "middle", "ring", "pinky", "little", "finger", "metacarpal"]
## In order of preference: the hand itself, then the end of the forearm.
const WRIST_WORDS: Array[String] = ["hand", "wrist", "forearm", "lowerarm", "lowarm", "arm2"]
## The band's radius over the forearm's length, and how far up the forearm from the wrist joint it sits: the
## first-person device's own fit (PlaylotMultiDevice WRIST_FIT, WRIST_BACK), so both views wear it alike.
const FIT := 0.16
const BACK := 0.22
## The device's band radius at scale 1 (PlaylotMultiDevice BAND_RADIUS), and a forearm for a rig with no parent bone.
const BAND := 0.05
const FOREARM := 0.25


## [param name] with the rig's prefix, case and separators removed: `mixamorig:LeftHand`,
## `Hand.L`, `hand_l` and `LeftHand` all read as a left hand.
static func normal(bone: String) -> String:
	var s := bone.to_lower()
	var colon := s.rfind(":")
	if colon >= 0:
		s = s.substr(colon + 1)
	return s


## True when the bone name says "left": a `left` word or a trailing `.l`, `_l`, `-l` or `l` after a letter.
static func is_left(bone: String) -> bool:
	return _is_side(bone, "left", "l")


## True when the bone name says "right", as [method is_left] reads "left".
static func is_right(bone: String) -> bool:
	return _is_side(bone, "right", "r")


static func _is_side(bone: String, word: String, letter: String) -> bool:
	var s := normal(bone)
	if s.contains(word):
		return true
	for sep in [".", "_", "-", " "]:
		if s.ends_with(sep + letter):
			return true
	return false


## The name of the right wrist bone in [param skeleton] (the hand, else the forearm), or "" when none
## reads as one. Fingers never match.
static func wrist_bone(skeleton: Skeleton3D) -> String:
	if skeleton == null:
		return ""
	for word in WRIST_WORDS:
		for i in range(skeleton.get_bone_count()):
			var bone := skeleton.get_bone_name(i)
			var s := normal(bone)
			if not s.contains(word) or not is_right(bone):
				continue
			var finger := false
			for f in FINGERS:
				if s.contains(f):
					finger = true
			if not finger:
				return bone
	return ""


## A node on [param figure]'s right wrist to hang the device from, or null (logged as an error) when the figure has no skeleton and no mount at all. [param who] names the player in the log.
## At rest the node's -Z runs down the forearm to the hand, +Y is as near the figure's up as that allows, and its scale fits the device's band to the forearm's length (so chibi and tall avatars wear it alike).
static func mount(figure: Node3D, who: String) -> Node3D:
	if figure == null:
		GSLog.error(CHANNEL, "multi-tool: no figure to mount on", {"player": who})
		return null
	var skeleton: Skeleton3D = figure.call(&"skeleton") if figure.has_method(&"skeleton") else null
	var bone := wrist_bone(skeleton)
	if bone != "":
		var attach := BoneAttachment3D.new()
		attach.name = "MultiToolBone"
		attach.bone_name = bone
		skeleton.add_child(attach)
		var node := Node3D.new()
		node.name = "MultiToolMount"
		attach.add_child(node)
		node.transform = _fit(skeleton, skeleton.find_bone(bone), figure.global_transform.basis)
		return node
	if figure.has_method(&"attachment"):
		var shared: Node3D = figure.call(&"attachment", &"hand")
		if shared != null:
			GSLog.warn(CHANNEL, "multi-tool: no wrist bone found by name, using the figure's hand mount", {
				"player": who, "bones": skeleton.get_bone_count() if skeleton != null else 0,
			})
			return shared
	GSLog.error(CHANNEL, "multi-tool: this figure has no wrist, no hand mount; the bracelet is not drawn", {"player": who})
	return null


## The mount's transform under bone [param index]'s attachment: along the forearm, upright, sized to it.
static func _fit(skeleton: Skeleton3D, index: int, figure: Basis) -> Transform3D:
	var to_world := skeleton.global_transform
	var at := to_world * skeleton.get_bone_global_rest(index)
	var ends := arm_ends(skeleton, index)
	var wrist: Vector3 = to_world * ends[0]
	var elbow: Vector3 = to_world * ends[1]
	var along := (wrist - elbow).normalized()
	var length := wrist.distance_to(elbow)
	var z := -along
	var up := figure.y.normalized()
	var y := up - z * up.dot(z)
	if y.length() < 0.2:
		y = -figure.z.normalized() - z * (-figure.z.normalized()).dot(z)
	y = y.normalized()
	var k := FIT * length / BAND
	var world := Transform3D(Basis(y.cross(z), y, z) * Basis.from_scale(Vector3.ONE * k), wrist + z * BACK * length)
	return at.affine_inverse() * world


## The wrist and the elbow at rest, skeleton space, for the bone [method wrist_bone] chose. A forearm bone
## starts at the elbow, so its wrist is where its child (the hand) starts; a hand bone starts at the wrist, and
## its elbow is the first ancestor a forearm away (twist bones skipped). A bare bone gets [constant FOREARM].
static func arm_ends(skeleton: Skeleton3D, index: int) -> Array[Vector3]:
	var origin := skeleton.get_bone_global_rest(index)
	var s := normal(skeleton.get_bone_name(index))
	var unit := FOREARM * 0.5
	if not s.contains("hand") and not s.contains("wrist"):
		var tip := Vector3.ZERO
		var found := false
		for child in skeleton.get_bone_children(index):
			var p := skeleton.get_bone_global_rest(child).origin
			if p.distance_to(origin.origin) > tip.distance_to(origin.origin) or not found:
				tip = p
				found = true
		if not found or tip.distance_to(origin.origin) < 0.01:
			tip = origin.origin + origin.basis.y.normalized() * FOREARM
		return [tip, origin.origin]
	var elbow := origin.origin - origin.basis.y.normalized() * FOREARM
	var parent := skeleton.get_bone_parent(index)
	for step in 3:
		if parent < 0:
			break
		var p := skeleton.get_bone_global_rest(parent).origin
		elbow = p
		if p.distance_to(origin.origin) >= unit:
			break
		parent = skeleton.get_bone_parent(parent)
	return [origin.origin, elbow]
