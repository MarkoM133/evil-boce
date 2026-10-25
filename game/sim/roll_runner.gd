class_name RollRunner
extends Node
## Runs one Roll at a time: launches the thrower, watches every ball it sets in motion and,
## once nothing is moving or snapping any more, emits the whole thing as a RollOutcome.
## Add it to the tree and `watch()` every ball that can take part.

signal finished(outcome: RollOutcome)

var _balls: Array[BallBody] = []
var _outcome: RollOutcome
var _running: bool = false
var _frames: int = 0
var _elapsed: float = 0.0


func watch(ball: BallBody) -> void:
	if _balls.has(ball):
		return
	_balls.append(ball)
	ball.roll_finished.connect(_on_roll_finished)


func unwatch(ball: BallBody) -> void:
	if not _balls.has(ball):
		return
	_balls.erase(ball)
	if ball.roll_finished.is_connected(_on_roll_finished):
		ball.roll_finished.disconnect(_on_roll_finished)


func unwatch_all() -> void:
	for b: BallBody in _balls.duplicate():
		if is_instance_valid(b):
			unwatch(b)
	_balls.clear()


func is_running() -> bool:
	return _running


## Throws `thrower`; `finished` fires when the table is still again. Ignored while a roll runs.
func start(thrower: BallBody, dir: Vector3, power: float) -> bool:
	return start_many([{"ball": thrower, "dir": dir, "power": power}])


## Launches several balls in the same frame (the Roll phase throws everything at once).
## Each entry is {"ball": BallBody, "dir": Vector3, "power": float}; the first is the
## outcome's thrower.
func start_many(throws: Array[Dictionary]) -> bool:
	if _running or throws.is_empty():
		return false
	_outcome = RollOutcome.new()
	_running = true
	_frames = 0
	_elapsed = 0.0
	for t: Dictionary in throws:
		var ball: BallBody = t["ball"]
		var dir: Vector3 = t["dir"]
		var power: float = t["power"]
		watch(ball)
		if _outcome.thrower.is_empty():
			_outcome.thrower = ball.ball_id
		ball.launch(dir, power)
	return true


func _physics_process(delta: float) -> void:
	if not _running:
		return
	_frames += 1
	_elapsed += delta
	# Give the launch a frame to register before checking for stillness.
	if _frames < 2:
		return
	for b: BallBody in _balls:
		if not is_instance_valid(b):
			continue
		if b.motion == BallBody.Motion.MOVING or b.motion == BallBody.Motion.SNAPPING:
			return
	_running = false
	_outcome.duration = _elapsed
	var out: RollOutcome = _outcome
	_outcome = null
	finished.emit(out)


func _on_roll_finished(_ball: BallBody, result: RollResult) -> void:
	if _running:
		_outcome.add(result)
