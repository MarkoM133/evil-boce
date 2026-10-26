class_name RollResult
extends RefCounted
## What one ball did between starting to move and coming to rest (or leaving the table).
## This is the data the rules engine gets from the physics; it never reads nodes. The sim only
## reports facts (where the ball went, what it touched); whether any of it counts as a
## ring-out is the engine's call.

var ball_id: String = ""
## True for a slingshot throw, false when the ball was knocked by another.
var thrown: bool = false
var power: float = 0.0
var start_hex: Vector2i = Vector2i.ZERO
## Hex the ball rests on. When it left the table, the last map hex it rolled over.
var end_hex: Vector2i = Vector2i.ZERO
## BallWorld.Area where the ball ended up (MAP, STRIP or VOID).
var end_area: int = 0
## True when the ball left the table (fell off the edge of the map or a strip).
var ring_out: bool = false
## "edge" (rolled past the playable surface) or "fell" (dropped below the table).
var ring_out_reason: String = ""
## Team whose start strip the ball rolled onto after having been on the map, or -1.
var strip_entered: int = -1
## Ids of balls this one hit, in order.
var collisions: PackedStringArray = PackedStringArray()
## Walls (static bodies in the "walls" group) this ball ran into, each counted once.
var walls_hit: int = 0
## Filled in step 2.
var cores_picked: PackedStringArray = PackedStringArray()
var stages_touched: PackedStringArray = PackedStringArray()
var duration: float = 0.0
var path: PackedVector3Array = PackedVector3Array()


## Metres travelled along the recorded path.
func path_length() -> float:
	var total: float = 0.0
	for i: int in range(1, path.size()):
		var a: Vector3 = path[i - 1]
		var b: Vector3 = path[i]
		total += Vector2(b.x - a.x, b.z - a.z).length()
	return total


## Straight-line distance from start to end, in metres.
func displacement() -> float:
	if path.size() < 2:
		return 0.0
	var a: Vector3 = path[0]
	var b: Vector3 = path[path.size() - 1]
	return Vector2(b.x - a.x, b.z - a.z).length()


func to_dict() -> Dictionary:
	var pts: Array = []
	for p: Vector3 in path:
		pts.append([snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01)])
	return {
		"ball": ball_id,
		"thrown": thrown,
		"power": snappedf(power, 0.001),
		"start_hex": [start_hex.x, start_hex.y],
		"end_hex": [end_hex.x, end_hex.y],
		"end_area": end_area,
		"ring_out": ring_out,
		"ring_out_reason": ring_out_reason,
		"strip_entered": strip_entered,
		"collisions": Array(collisions),
		"walls_hit": walls_hit,
		"cores_picked": Array(cores_picked),
		"stages_touched": Array(stages_touched),
		"duration": snappedf(duration, 0.001),
		"path": pts,
	}


## Inverse of to_dict(); tolerant of missing keys and JSON floats.
static func from_dict(d: Dictionary) -> RollResult:
	var r := RollResult.new()
	r.ball_id = str(d.get("ball", ""))
	r.thrown = JsonUtil.as_bool(d.get("thrown", false))
	r.power = JsonUtil.as_float(d.get("power", 0.0))
	r.start_hex = JsonUtil.as_hex(d.get("start_hex", null))
	r.end_hex = JsonUtil.as_hex(d.get("end_hex", null))
	r.end_area = JsonUtil.as_int(d.get("end_area", 0))
	r.ring_out = JsonUtil.as_bool(d.get("ring_out", false))
	r.ring_out_reason = str(d.get("ring_out_reason", ""))
	r.strip_entered = JsonUtil.as_int(d.get("strip_entered", -1), -1)
	r.collisions = JsonUtil.as_strings(d.get("collisions", []))
	r.walls_hit = JsonUtil.as_int(d.get("walls_hit", 0))
	r.cores_picked = JsonUtil.as_strings(d.get("cores_picked", []))
	r.stages_touched = JsonUtil.as_strings(d.get("stages_touched", []))
	r.duration = JsonUtil.as_float(d.get("duration", 0.0))
	for p: Variant in JsonUtil.as_array(d.get("path", [])):
		var xyz: Array = JsonUtil.as_array(p)
		if xyz.size() == 3:
			r.path.append(Vector3(JsonUtil.as_float(xyz[0]), JsonUtil.as_float(xyz[1]), JsonUtil.as_float(xyz[2])))
	return r
