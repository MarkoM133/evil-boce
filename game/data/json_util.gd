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


static func as_array(v: Variant) -> Array:
	if v is Array:
		var a: Array = v
		return a
	return []
