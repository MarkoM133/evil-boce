class_name BallWorld
extends RefCounted
## What a ball needs to know about the ground under it. The default is an endless flat map
## with no terrain and no snapping (used by tools/measure_throws.gd).

enum Area { MAP, STRIP, VOID }

var tuning: PhysicsTuning


func _init(tuning_: PhysicsTuning) -> void:
	tuning = tuning_


func area_at(_pos: Vector3) -> Area:
	return Area.MAP


## Team whose start strip is under `pos`, or -1.
func strip_at(_pos: Vector3) -> int:
	return -1


## Multiplier for the rolling slow-down at this point.
func friction_factor_at(_pos: Vector3) -> float:
	return 1.0


## Extra horizontal acceleration on a rolling ball here (hill slope, wind), m/s^2 as (x, z).
func push_at(_pos: Vector3) -> Vector2:
	return Vector2.ZERO


## Height of the ground here (a hill), for drawing the ball on top of it.
func height_at(_pos: Vector3) -> float:
	return 0.0


func hex_at(pos: Vector3) -> Vector2i:
	return Hex.from_world(Vector2(pos.x, pos.z), tuning.hex_size)


## Where a ball that just stopped should slide to.
func snap_point(ball: BallBody) -> Vector3:
	return ball.global_position
