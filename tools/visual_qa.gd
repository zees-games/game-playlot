extends GSGameVisualQaCapture

## Playlot's visual QA capture for the people (gs-game docs/visual-qa.md): one item per site skin (`person_a` .. `person_r`, the kit's eighteen), each idling, walking, running a circle and jumping, seen from the front, behind-right and the centre of the circle, at 60 fps. The weapons and the player's first-person view are tools/anim_review.gd (docs/anim-review.md); this is the body every other player sees.
## Run: bash tools/visual_qa_shot.sh --only person_a,person_k --clips walk,run

const PlaylotAvatars := preload("../game/playlot_avatars.gd")
const PlaylotFigure := preload("../game/playlot_figure.gd")

const PERSON_HEIGHT := 1.8
const CIRCLE_RADIUS := 3.0
## Ground speed (m/s) and the motion the figure is told, per clip.
const CLIPS := {
	"idle": [0.0, {}], "walk": [3.5, {}], "run": [7.0, {}],
	"jump": [7.0, {"on_floor": false, "vertical": 3.0}],
}

var _fig: GSHumanoidFigure = null
var _item := ""


func _items() -> PackedStringArray:
	var out := PackedStringArray()
	for letter in PlaylotAvatars.LETTERS:
		out.append("person_" + letter)
	return out


func _clips(_item_id: String) -> PackedStringArray:
	return PackedStringArray(CLIPS.keys())


func _stage(item: String, clip: String) -> GSResult:
	if _item != item:
		if _fig != null:
			_fig.queue_free()
		var skin := PlaylotAvatars.LETTERS.find(item.trim_prefix("person_"))
		if skin < 0:
			return GSResult.fail(GSError.CODE_INVALID, "no skin for %s" % item)
		var person := PlaylotFigure.build(PERSON_HEIGHT, PackedInt32Array([skin, skin, skin]), item)
		_fig = PlaylotFigure.person_of(person)
		if _fig == null:
			return GSResult.fail(GSError.CODE_INVALID, "the people's art did not load")
		root.add_child(_fig)
		_item = item
	_fig.position = Vector3(0.0, 0.0, -CIRCLE_RADIUS)
	_fig.rotation = Vector3.ZERO
	return GSResult.success(clip)


func _subject(_item_id: String) -> Node3D:
	return _fig


func _seconds(_item_id: String, _clip: String) -> float:
	return 3.0


func _grounded(_item_id: String, clip: String, _t: float) -> bool:
	return clip != "jump"


func _drive(_item_id: String, clip: String, t: float, _frame: int) -> void:
	var def: Array = CLIPS[clip]
	var speed: float = def[0]
	var angle := speed * t / CIRCLE_RADIUS
	var from := _fig.position
	if speed > 0.0:
		_fig.position = Vector3(sin(angle), 0.0, -cos(angle)) * CIRCLE_RADIUS
		_fig.rotation.y = -angle
	var motion: Dictionary = (def[1] as Dictionary).duplicate()
	motion["alive"] = true
	motion["speed"] = speed
	motion["velocity"] = (_fig.position - from) * float(fps)
	if clip == "jump":
		_fig.position.y = maxf(0.0, 0.9 * sin(fposmod(t, 0.6) / 0.6 * PI))
		motion["vertical"] = 3.0 if fposmod(t, 0.6) < 0.3 else -3.0
	_fig.set_motion(motion)
	_fig.animate(speed, 1.0 / float(fps))


## The centre of the circle, looking at the person.
func _place_first_person(_item_id: String) -> void:
	first_person.global_position = Vector3(0.0, 1.6, 0.0)
	first_person.look_at(_fig.global_position + Vector3(0.0, 1.0, 0.0))
