class_name PhysicsTuning
extends Resource
## Every physics number lives here; the instance is sim/physics_tuning.tres.
## Per-WT arrays: index 0 = WT 1 ... last entry = WT 4 and above.

@export_group("Grid")
## Hex circumradius in metres.
@export var hex_size: float = 1.0

@export_group("Balls by WT")
@export var radius_by_wt: PackedFloat32Array = PackedFloat32Array([0.5, 0.62, 0.75, 1.3])
@export var mass_by_wt: PackedFloat32Array = PackedFloat32Array([1.0, 1.6, 2.4, 4.0])
## How far a full-power throw goes on plain ground, in hexes.
@export var full_power_hexes_by_wt: PackedFloat32Array = PackedFloat32Array([18.0, 15.0, 12.0, 9.0])
## From this WT up a ball covers 7 hexes.
@export var big_from_wt: int = 4

## Highest WT the sim accepts; larger values are clamped.
@export var max_wt: int = 9

@export_group("Rolling")
## Constant slow-down on plain ground, m/s^2. Higher = shorter rolls.
@export var deceleration: float = 9.0
## Below this speed (m/s) a ball counts as stopped.
@export var stop_speed: float = 0.12
## Physics frames below stop_speed before the ball counts as stopped.
@export var rest_frames: int = 4
## A resting ball pushed faster than this (m/s) starts a roll of its own.
@export var wake_speed: float = 0.24
## Ball-to-ball bounciness, 0 = dead, 1 = perfect billiards.
@export var ball_bounce: float = 0.9
## Physics frames between two recorded path points.
@export var path_sample_every: int = 3

@export_group("Slingshot")
## Speed = full speed * power ^ exponent. 0.5 makes distance linear in drag length.
@export var power_exponent: float = 0.5
## Shorter pulls than this are clicks, not throws.
@export var min_power: float = 0.03
## Full power = drag of this fraction of the screen height.
@export var max_drag_screen_fraction: float = 0.3

@export_group("Snap")
@export var snap_time: float = 0.16

@export_group("Terrain")
## Multiplies deceleration on that terrain.
@export var ice_factor: float = 0.35
@export var mud_factor: float = 2.6

@export_group("Ring-out")
## A ball below this height (m) has fallen off the table.
@export var fell_below_y: float = -3.0
## Seconds a ringed-out ball keeps falling before it goes back to its strip.
@export var ring_out_return_delay: float = 1.0


static func load_default() -> PhysicsTuning:
	return load("res://sim/physics_tuning.tres") as PhysicsTuning


func _index(wt: int, arr: PackedFloat32Array) -> int:
	return clampi(wt, 1, arr.size()) - 1


func radius(wt: int) -> float:
	return radius_by_wt[_index(wt, radius_by_wt)]


func mass(wt: int) -> float:
	return mass_by_wt[_index(wt, mass_by_wt)]


func full_power_hexes(wt: int) -> float:
	return full_power_hexes_by_wt[_index(wt, full_power_hexes_by_wt)]


func is_big(wt: int) -> bool:
	return wt >= big_from_wt


func hex_spacing() -> float:
	return hex_size * Hex.SQRT3


## Launch speed at full power, so that the ball stops after full_power_hexes on plain ground.
func launch_speed(wt: int) -> float:
	return sqrt(2.0 * deceleration * full_power_hexes(wt) * hex_spacing())


func terrain_factor(t: Terrain.Type) -> float:
	match t:
		Terrain.Type.ICE:
			return ice_factor
		Terrain.Type.MUD:
			return mud_factor
	return 1.0
