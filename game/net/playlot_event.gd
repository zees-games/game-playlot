extends GSNetMessage

const PlaylotEvents := preload("playlot_events.gd")

## Anything the authority tells a client that is not a snapshot. Reliable, to clients.

const NAME := &"pg.event"
const KIND_BITS := 5
const MAX_BODY := 16384

var kind: int = 0
var body: PackedByteArray = PackedByteArray()


## [b]Built with [code]new(kind, body)[/code], and this file does not preload itself.[/b]
## It used to, for a typed [code]static func of() -> PlaylotEvent[/code] factory. A script that
## [code]extends GSNetMessage[/code] and preloads ITSELF, first loaded from a module a
## running [GSServer] loads at runtime — which is how every deployed server loads this
## game — leaks the whole script graph at exit on Godot 4.7.2. Measured in
## mg-buses-from-hell (8ed866c) with a two-line reproduction. The registry decodes with a
## bare [code]new()[/code], which is why both arguments default.
func _init(p_kind: int = 0, p_body: PackedByteArray = PackedByteArray()) -> void:
	kind = p_kind
	body = p_body


func _type_name() -> StringName:
	return NAME


func _write(writer: GSNetWriter) -> void:
	writer.write_uint(kind, KIND_BITS)
	writer.write_bytes(body)


func _read(reader: GSNetReader) -> void:
	kind = reader.read_uint(KIND_BITS)
	body = reader.read_bytes(MAX_BODY)


func _validate() -> GSResult:
	if kind < 0 or kind >= PlaylotEvents.Kind.size():
		return GSResult.fail(GSError.CODE_INVALID, "Unknown event kind %d." % kind)
	return GSResult.success(true)


## Whether every [enum PlaylotEvents.Kind] fits in [constant KIND_BITS]. What a check reads: the writer
## masks a value to its field, so a kind past it goes out as a smaller one and nothing errors.
static func fits() -> bool:
	return int(PlaylotEvents.Kind.values().max()) < (1 << KIND_BITS)


func reader() -> GSNetReader:
	return GSNetReader.new(body)


func _to_string() -> String:
	return "PlaylotEvent(%s, %d bytes)" % [PlaylotEvents.kind_name(kind), body.size()]
