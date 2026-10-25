class_name RollOutcome
extends RefCounted
## Everything one Roll did: the thrown ball and every ball it set in motion, each as a
## RollResult, in the order they started moving (thrower first). This is the one packet the
## rules engine receives per Roll; tests and replays build it from JSON.

var thrower: String = ""
var results: Array[RollResult] = []
## Seconds from the launch until the last ball came to rest.
var duration: float = 0.0


func result_for(ball_id: String) -> RollResult:
	for r: RollResult in results:
		if r.ball_id == ball_id:
			return r
	return null


func thrower_result() -> RollResult:
	return result_for(thrower)


## Ids of every ball that moved, thrower first.
func moved_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for r: RollResult in results:
		out.append(r.ball_id)
	return out


## Records a finished ball. A ball knocked more than once in the same roll keeps one entry:
## its latest end state, with the collisions and path of every leg joined up.
func add(r: RollResult) -> void:
	var prev: RollResult = result_for(r.ball_id)
	if prev == null:
		results.append(r)
		return
	var merged := RollResult.new()
	merged.ball_id = r.ball_id
	merged.thrown = prev.thrown or r.thrown
	merged.power = maxf(prev.power, r.power)
	merged.start_hex = prev.start_hex
	merged.end_hex = r.end_hex
	merged.end_area = r.end_area
	merged.ring_out = r.ring_out
	merged.ring_out_reason = r.ring_out_reason
	merged.strip_entered = prev.strip_entered if prev.strip_entered >= 0 else r.strip_entered
	merged.collisions = prev.collisions + r.collisions
	merged.cores_picked = prev.cores_picked + r.cores_picked
	merged.stages_touched = prev.stages_touched + r.stages_touched
	merged.duration = prev.duration + r.duration
	merged.path = prev.path + r.path
	results[results.find(prev)] = merged


func to_dict() -> Dictionary:
	var list: Array = []
	for r: RollResult in results:
		list.append(r.to_dict())
	return {
		"thrower": thrower,
		"duration": snappedf(duration, 0.001),
		"results": list,
	}


static func from_dict(d: Dictionary) -> RollOutcome:
	var o := RollOutcome.new()
	o.thrower = str(d.get("thrower", ""))
	o.duration = JsonUtil.as_float(d.get("duration", 0.0))
	for item: Variant in JsonUtil.as_array(d.get("results", [])):
		if item is Dictionary:
			var rd: Dictionary = item
			o.results.append(RollResult.from_dict(rd))
	return o
