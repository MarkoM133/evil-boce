extends GutTest
## The game's cursor (item 19, C1): its three drawings become pictures of the right size.


func _picture(svg: String, k: float) -> Image:
	var img := Image.new()
	assert_eq(img.load_svg_from_string(svg, k), OK)
	return img


func test_the_drawings_become_32_px_pictures() -> void:
	for svg: String in [GameCursor.dart_svg(false), GameCursor.dart_svg(true), GameCursor.diamond_svg()]:
		var img: Image = _picture(svg, 1.0)
		assert_eq(img.get_size(), Vector2i(32, 32))
		assert_false(img.is_invisible(), "something is drawn")


func test_the_arrow_is_straw_at_rest_and_red_over_what_can_be_clicked() -> void:
	# Inside the dart's light part: off its dark facet, its rim and the highlight line of the red one.
	var rest: Color = _picture(GameCursor.dart_svg(false), 1.0).get_pixel(18, 12)
	var over: Color = _picture(GameCursor.dart_svg(true), 1.0).get_pixel(18, 12)
	assert_almost_eq(rest.r, Color(GameCursor.GOLD).r, 0.08)
	assert_almost_eq(rest.g, Color(GameCursor.GOLD).g, 0.08)
	assert_almost_eq(over.r, Color(GameCursor.RED).r, 0.08)
	assert_true(over.g < 0.2, "red, not straw")


func test_a_bigger_window_gets_a_bigger_cursor() -> void:
	assert_eq(GameCursor.scale_for(720), 1.0, "never smaller than drawn")
	assert_eq(GameCursor.scale_for(900), 1.0)
	assert_almost_eq(GameCursor.scale_for(1440), 1.6, 0.001)
	assert_eq(GameCursor.scale_for(4320), 2.5, "at most two and a half times")
	assert_eq(_picture(GameCursor.diamond_svg(), 2.0).get_size(), Vector2i(64, 64))
