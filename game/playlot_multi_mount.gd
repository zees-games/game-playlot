extends RefCounted
## Where the multi-tool's bracelet sits on a person: the wrist, found on whatever rig the avatar has.
##
## [b]Tolerant, then shared, then loud.[/b] The family's figure hands out a hand mount
## ([code]GSHumanoidFigure.attachment[/code]); a rig whose bones are named another way (a
## library avatar, a `mixamorig:` rig, `lowerarm_l`) still gets the bracelet, on the bone this
## finds by reading the names, and a rig with nothing that looks like an arm is drawn at the
## figure's own fallback spot with an error in the log, never silently.

const CHANNEL := "playlot.multi.mount"

## Words that make a bone a finger, not a wrist.
const FINGERS: Array[String] = ["thumb", "index", "middle", "ring", "pinky", "little", "finger", "metacarpal"]
## In order of preference: the hand itself, then the end of the forearm.
const WRIST_WORDS: Array[String] = ["hand", "wrist", "forearm", "lowerarm", "lowarm", "arm2"]


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
	var s := normal(bone)
	if s.contains("left"):
		return true
	for tail in [".l", "_l", "-l", " l"]:
		if s.ends_with(tail):
			return true
	return false


## The name of the left wrist bone in [param skeleton] (the hand, else the forearm), or "" when none
## reads as one. Fingers never match.
static func wrist_bone(skeleton: Skeleton3D) -> String:
	if skeleton == null:
		return ""
	for word in WRIST_WORDS:
		for i in range(skeleton.get_bone_count()):
			var bone := skeleton.get_bone_name(i)
			var s := normal(bone)
			if not s.contains(word) or not is_left(bone):
				continue
			var finger := false
			for f in FINGERS:
				if s.contains(f):
					finger = true
			if not finger:
				return bone
	return ""


## A node on [param figure]'s left wrist to hang the device from, or null (logged as an error) when
## the figure has no skeleton and no mount at all. [param who] names the player in the log.
## The node's axes are the figure's own (-Z forward, +Y up) at rest, whatever the bone's axes are.
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
		var index := skeleton.find_bone(bone)
		var rest := skeleton.global_transform.basis * skeleton.get_bone_global_rest(index).basis
		node.transform = Transform3D(rest.inverse() * figure.global_transform.basis, Vector3.ZERO)
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
