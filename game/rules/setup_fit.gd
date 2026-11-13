class_name SetupFit
extends RefCounted
## Whether `count` more pieces still fit on the free hexes of a setup (Marko 2026-11-13: placing stages one by one
## could box the last one out, and the bot then stood still for ever). Two pieces conflict when their centres are
## closer than `min_dist`. A search over the free hexes: the first free hex is used, or one of the hexes it conflicts
## with is (were neither in a full layout, the first could be added to it), so nothing is missed. The work is
## capped: past BUDGET steps it says "fits" and the setup's smaller-gap fallback covers what that may let through.

const BUDGET: int = 4000


static func fits(free: Array[Vector2i], count: int, min_dist: int) -> bool:
	var steps: Array[int] = [0]
	return _fits(free, count, min_dist, steps)


static func _fits(free: Array[Vector2i], count: int, min_dist: int, steps: Array[int]) -> bool:
	if count <= 0:
		return true
	if free.size() < count:
		return false
	# A piece rules out at most the hexes within min_dist - 1 of it, so with this many free the rest always fit.
	var reach: int = min_dist - 1
	if free.size() > (count - 1) * (1 + 3 * reach * (reach + 1)):
		return true
	steps[0] += 1
	if steps[0] > BUDGET:
		return true
	var first: Vector2i = free[0]
	for pick: Vector2i in free:
		if pick != first and Hex.distance(pick, first) >= min_dist:
			continue
		if _fits(without(free, pick, min_dist), count - 1, min_dist, steps):
			return true
	return false


## `free` without the hexes a piece on `at` rules out (itself too).
static func without(free: Array[Vector2i], at: Vector2i, min_dist: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for a: Vector2i in free:
		if Hex.distance(a, at) >= min_dist:
			out.append(a)
	return out
