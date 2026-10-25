class_name Hex
extends RefCounted
## Hex math: pointy-top hexes, axial coordinates (q, r), stored as Vector2i(q, r).
## World positions are on the table plane, as Vector2(x, z). See docs/hex.md.

const SQRT3: float = 1.7320508075688772

## Neighbour offsets. Index i points at angle 60 * i degrees in the (x, z) plane,
## so 0 = +x, 1 = +z side, 3 = -x.
const DIRECTIONS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 1),
	Vector2i(-1, 0), Vector2i(0, -1), Vector2i(1, -1),
]


## Centre of hex `a` for hexes with circumradius `size`.
static func to_world(a: Vector2i, size: float) -> Vector2:
	return Vector2(size * SQRT3 * (a.x + a.y * 0.5), size * 1.5 * a.y)


## Hex that contains world point `p`.
static func from_world(p: Vector2, size: float) -> Vector2i:
	var q: float = (SQRT3 / 3.0 * p.x - p.y / 3.0) / size
	var r: float = (2.0 / 3.0 * p.y) / size
	return cube_round(q, r)


static func cube_round(q: float, r: float) -> Vector2i:
	var s: float = -q - r
	var rq: float = roundf(q)
	var rr: float = roundf(r)
	var rs: float = roundf(s)
	var dq: float = absf(rq - q)
	var dr: float = absf(rr - r)
	var ds: float = absf(rs - s)
	if dq > dr and dq > ds:
		rq = -rr - rs
	elif dr > ds:
		rr = -rq - rs
	return Vector2i(int(rq), int(rr))


@warning_ignore("integer_division")
static func distance(a: Vector2i, b: Vector2i) -> int:
	var d: Vector2i = a - b
	return (absi(d.x) + absi(d.y) + absi(d.x + d.y)) / 2


static func neighbor(a: Vector2i, dir: int) -> Vector2i:
	return a + DIRECTIONS[posmod(dir, 6)]


## Index of the DIRECTIONS entry that points most nearly from `from` towards `to`
## (0 when they coincide). Used for grid knockback.
static func direction_towards(from: Vector2i, to: Vector2i) -> int:
	if from == to:
		return 0
	var v: Vector2 = to_world(to, 1.0) - to_world(from, 1.0)
	var best: int = 0
	var best_dot: float = -INF
	for i: int in 6:
		var d: Vector2 = to_world(DIRECTIONS[i], 1.0)
		var dot: float = v.normalized().dot(d.normalized())
		if dot > best_dot:
			best_dot = dot
			best = i
	return best


## Hex coordinates as JSON: [q, r].
static func to_json(a: Vector2i) -> Array:
	return [a.x, a.y]


static func neighbors(a: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for d: Vector2i in DIRECTIONS:
		out.append(a + d)
	return out


## Hexes at exactly `radius` steps from `center`.
static func ring(center: Vector2i, radius: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if radius <= 0:
		out.append(center)
		return out
	var cur: Vector2i = center + DIRECTIONS[4] * radius
	for i: int in 6:
		for _j: int in radius:
			out.append(cur)
			cur = cur + DIRECTIONS[i]
	return out


## Hexes at most `radius` steps from `center`, centre first.
static func spiral(center: Vector2i, radius: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = [center]
	for k: int in range(1, radius + 1):
		out.append_array(ring(center, k))
	return out


## Odd-r offset (col, row) -> axial. Odd rows are shifted half a hex to +x.
@warning_ignore("integer_division")
static func offset_to_axial(col: int, row: int) -> Vector2i:
	return Vector2i(col - (row - (row & 1)) / 2, row)


@warning_ignore("integer_division")
static func axial_to_offset(a: Vector2i) -> Vector2i:
	return Vector2i(a.x + (a.y - (a.y & 1)) / 2, a.y)


## Corner i of a hex, relative to its centre; corner i sits at 30 + 60 * i degrees.
## Edge (corner i-1, corner i) faces DIRECTIONS[i].
static func corner(i: int, size: float) -> Vector2:
	var ang: float = deg_to_rad(30.0 + 60.0 * i)
	return Vector2(cos(ang), sin(ang)) * size
