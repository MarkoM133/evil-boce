extends GutTest


func test_numbers() -> void:
	assert_eq(JsonUtil.as_int(3.0), 3)
	assert_eq(JsonUtil.as_int("7"), 7)
	assert_eq(JsonUtil.as_int("x", 5), 5)
	assert_almost_eq(JsonUtil.as_float(2), 2.0, 0.0001)
	assert_almost_eq(JsonUtil.as_float("1.5"), 1.5, 0.0001)
	assert_almost_eq(JsonUtil.as_float(null, 9.0), 9.0, 0.0001)


func test_packed_arrays_count_as_arrays() -> void:
	# The match setup hands the bot slots over as a PackedInt32Array.
	assert_eq(JsonUtil.as_array(PackedInt32Array([1])), [1])
	assert_eq(JsonUtil.as_array(PackedStringArray(["a"])), ["a"])
	assert_eq(JsonUtil.as_array("x"), [])


func test_hex_and_strings() -> void:
	assert_eq(JsonUtil.as_hex([3.0, -2.0]), Vector2i(3, -2))
	assert_eq(JsonUtil.as_hex([1]), Vector2i.ZERO)
	assert_eq(JsonUtil.as_hex(null, Vector2i(9, 9)), Vector2i(9, 9))
	assert_eq(JsonUtil.as_strings(["a", 2, "c"]), PackedStringArray(["a", "2", "c"]))
	assert_eq(JsonUtil.as_strings(null).size(), 0)
