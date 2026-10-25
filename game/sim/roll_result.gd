class_name RollResult
extends RefCounted
## What one ball did between starting to move and coming to rest (or leaving the map).
## This is the data the rules engine gets from the physics; it never reads nodes.

var ball_id: String = ""
## True for a slingshot throw, false when the ball was knocked by another.
var thrown: bool = false
var power: float = 0.0
var start_hex: Vector2i = Vector2i.ZERO
var end_hex: Vector2i = Vector2i.ZERO
## BallWorld.Area where the ball ended up (MAP, STRIP or VOID).
var end_area: int = 0
var ring_out: bool = false
## "edge" (off the map), "strip" (onto a start strip) or "fell".
var ring_out_reason: String = ""
## Ids of balls this one hit, in order.
var collisions: PackedStringArray = PackedStringArray()
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
		"collisions": Array(collisions),
		"cores_picked": Array(cores_picked),
		"stages_touched": Array(stages_touched),
		"duration": snappedf(duration, 0.001),
		"path": pts,
	}
