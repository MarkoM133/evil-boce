class_name JsonUtil
extends RefCounted
## Typed reads from parsed JSON (numbers come back as float, anything may be missing).


static func as_int(v: Variant, fallback: int = 0) -> int:
	if v is int:
		var i: int = v
		return i
	if v is float:
		var f: float = v
		return roundi(f)
	if v is String:
		var s: String = v
		return s.to_int() if s.is_valid_int() else fallback
	return fallback


static func as_float(v: Variant, fallback: float = 0.0) -> float:
	if v is float:
		var f: float = v
		return f
	if v is int:
		var i: int = v
		return float(i)
	if v is String:
		var s: String = v
		return s.to_float() if s.is_valid_float() else fallback
	return fallback


## A hex written as [q, r].
static func as_hex(v: Variant, fallback: Vector2i = Vector2i.ZERO) -> Vector2i:
	var a: Array = as_array(v)
	if a.size() != 2:
		return fallback
	return Vector2i(as_int(a[0]), as_int(a[1]))


static func as_strings(v: Variant) -> PackedStringArray:
	if v is PackedStringArray:
		var packed: PackedStringArray = v
		return packed.duplicate()
	var out := PackedStringArray()
	for s: Variant in as_array(v):
		out.append(str(s))
	return out


static func as_bool(v: Variant, fallback: bool = false) -> bool:
	if v is bool:
		var b: bool = v
		return b
	if v is int or v is float:
		return as_int(v) != 0
	return fallback


static func as_dict(v: Variant) -> Dictionary:
	if v is Dictionary:
		var d: Dictionary = v
		return d
	return {}


## Arrays, and packed arrays (they come from code, not from JSON) as a plain Array.
static func as_array(v: Variant) -> Array:
	if v is Array:
		var a: Array = v
		return a
	var out: Array = []
	if v is PackedInt32Array or v is PackedInt64Array or v is PackedStringArray or v is PackedFloat32Array \
			or v is PackedFloat64Array or v is PackedVector2Array:
		for x: Variant in v:
			out.append(x)
	return out
