extends RefCounted
## The icons the multi-tool's screen shows, one per mode, drawn once from distance functions and
## cached: a mode's icon is a 64 x 64 texture shared by every device on screen, so the screen is
## one quad and one texture per mode however many players wear the tool.

const SIZE := 64

static var _cache: Dictionary = {}


## The icon of [param mode] in its glow colour on a dark panel.
static func texture(mode: StringName, colour: Color) -> ImageTexture:
	var cached: Variant = _cache.get(mode)
	if cached != null:
		return cached as ImageTexture
	var made := ImageTexture.create_from_image(_draw(mode, colour))
	_cache[mode] = made
	return made


static func _draw(mode: StringName, colour: Color) -> Image:
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var back := colour.darkened(0.88)
	for y in SIZE:
		for x in SIZE:
			var p := Vector2((float(x) + 0.5) / SIZE * 2.0 - 1.0, (float(y) + 0.5) / SIZE * 2.0 - 1.0)
			var edge := maxf(absf(p.x), absf(p.y))
			var c := back
			# A faint scanline texture and a lit border so the panel reads as a display.
			if y % 4 == 0:
				c = c.lightened(0.06)
			if edge > 0.9:
				c = c.lerp(colour, smoothstep(0.9, 0.96, edge) * 0.8)
			var ink := clampf(_shape(mode, p), 0.0, 1.0)
			c = c.lerp(colour.lightened(0.25), ink)
			c.a = 1.0
			img.set_pixel(x, y, c)
	return img


## 1 inside the glyph, 0 outside, a pixel of falloff between.
static func _shape(mode: StringName, p: Vector2) -> float:
	var r := p.length()
	var a := atan2(p.y, p.x)
	match mode:
		&"phys":
			# A grabber: a ring round a dot.
			return maxf(_ring(r, 0.58, 0.1), _disc(r, 0.2))
		&"grav":
			# Field lines: two broken rings round a dot.
			var gap := absf(sin(a * 2.0)) > 0.35
			var broken := maxf(_ring(r, 0.4, 0.07), _ring(r, 0.72, 0.07)) if gap else 0.0
			return maxf(broken, _disc(r, 0.15))
		&"impulse":
			# A burst: eight rays off a core.
			var ray := 1.0 if absf(sin(a * 4.0)) > 0.8 else 0.0
			var span := _ring(r, 0.62, 0.2) if ray > 0.0 else 0.0
			return maxf(span, _disc(r, 0.2))
		&"spawn":
			# A plus: something to put into the world.
			var bar := 0.11
			var h := _box(p, Vector2(0.62, bar))
			var v := _box(p, Vector2(bar, 0.62))
			return maxf(h, v)
		&"remover":
			# A cross: take it away.
			var d1 := absf(p.x - p.y) * 0.7071
			var d2 := absf(p.x + p.y) * 0.7071
			var within := maxf(absf(p.x), absf(p.y)) < 0.64
			var cross := maxf(1.0 - smoothstep(0.08, 0.13, d1), 1.0 - smoothstep(0.08, 0.13, d2))
			return cross if within else 0.0
		&"toolgun":
			# A cog: a ring with teeth and a hole.
			var tooth := 1.0 if cos(a * 6.0) > 0.2 else 0.0
			var body := _ring(r, 0.42, 0.17)
			var teeth := _ring(r, 0.66, 0.1) if tooth > 0.0 else 0.0
			return maxf(body, teeth)
	return 0.0


static func _disc(r: float, radius: float) -> float:
	return 1.0 - smoothstep(radius - 0.04, radius + 0.04, r)


static func _ring(r: float, radius: float, half_width: float) -> float:
	return 1.0 - smoothstep(half_width - 0.04, half_width + 0.04, absf(r - radius))


static func _box(p: Vector2, half: Vector2) -> float:
	var d := maxf(absf(p.x) - half.x, absf(p.y) - half.y)
	return 1.0 - smoothstep(-0.04, 0.04, d)
