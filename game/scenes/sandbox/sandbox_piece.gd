class_name SandboxPiece
extends RefCounted
## A hero ball in the sandbox: card data, sandbox overrides, physics body and view.

var hero: HeroDef
var team: int = 0
var rng: int = 3
var hp: int = 10
var body: BallBody
var view: BallView
## Seconds left until a ringed-out ball goes back to its strip; < 0 when not waiting.
var return_in: float = -1.0
## Last throw this ball took part in, for the path display.
var last_path: PackedVector3Array = PackedVector3Array()


func label() -> String:
	return hero.name
