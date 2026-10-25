class_name LoadoutPicker
extends VBoxContainer
## Stages and cores for one player (GDD 7), folded into one line until opened: three stage
## pickers and two core pickers per kind, each with Random. Edits `loadout` in place.

signal changed

const RANDOM_TEXT: String = "Random"

var loadout: Loadout = Loadout.new()
var _catalog: CardCatalog
var _toggle: Button
var _body: VBoxContainer
var _stage_picks: Array[OptionButton] = []
var _core_picks: Array[OptionButton] = []
var _problems: Label
var _title: String = ""


## `title` heads the folded line ("Player 1", "Your stages and cores").
func setup(catalog: CardCatalog, start: Loadout, title: String) -> void:
	_catalog = catalog
	loadout = start
	_title = title
	add_theme_constant_override("separation", 6)
	_toggle = Button.new()
	_toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_toggle.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_toggle.pressed.connect(func() -> void:
		_body.visible = not _body.visible
		_refresh())
	add_child(_toggle)
	_body = VBoxContainer.new()
	_body.visible = false
	_body.add_theme_constant_override("separation", 6)
	add_child(_body)

	var stages: Array[CardDef] = catalog.of_type("Stage")
	var row := _row("Stages")
	for i: int in Loadout.STAGES:
		var o := _picker(row)
		for st: CardDef in stages:
			var terrain: String = Terrain.name_of(st.terrain) if st.terrain != Terrain.Type.NONE else ""
			o.add_item(st.name + ("  ·  " + terrain if not terrain.is_empty() else ""))
			o.set_item_metadata(o.item_count - 1, st.id)
		_select_id(o, loadout.stages[i])
		o.item_selected.connect(func(_x: int) -> void:
			loadout.stages[i] = str(o.get_selected_metadata())
			_refresh()
			changed.emit())
		_stage_picks.append(o)
	var cores: Array[CardDef] = catalog.of_type("Core")
	for k: int in Loadout.CORE_KINDS.size():
		var kind: String = Loadout.CORE_KINDS[k]
		row = _row(kind + " cores")
		for j: int in Loadout.CORES_PER_KIND:
			var slot: int = k * Loadout.CORES_PER_KIND + j
			var o := _picker(row)
			for c: CardDef in cores:
				if c.kind == kind:
					o.add_item(c.name)
					o.set_item_metadata(o.item_count - 1, c.id)
			_select_id(o, loadout.cores[slot])
			o.item_selected.connect(func(_x: int) -> void:
				loadout.cores[slot] = str(o.get_selected_metadata())
				_refresh()
				changed.emit())
			_core_picks.append(o)
	_problems = Label.new()
	_problems.theme_type_variation = &"Muted"
	_problems.add_theme_color_override("font_color", Palette.GOLD)
	_problems.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(_problems)
	var all_random := Button.new()
	all_random.text = "All random"
	all_random.size_flags_horizontal = Control.SIZE_SHRINK_END
	all_random.pressed.connect(func() -> void:
		loadout = Loadout.random()
		for o: OptionButton in _stage_picks + _core_picks:
			o.select(0)
		_refresh()
		changed.emit())
	_body.add_child(all_random)
	_refresh()


func problems() -> PackedStringArray:
	return loadout.problems(_catalog)


## One line for the folded state: "Drum Island, Random, Random  ·  cores random".
func summary() -> String:
	var names := PackedStringArray()
	for id: String in loadout.stages:
		var c: CardDef = _catalog.get_card(id) if not id.is_empty() else null
		names.append(c.name if c != null else RANDOM_TEXT)
	var picked: int = 0
	for id: String in loadout.cores:
		if not id.is_empty():
			picked += 1
	var cores: String = "cores random" if picked == 0 else "%d of 6 cores picked" % picked
	return "%s  ·  %s" % [", ".join(names), cores]


func _refresh() -> void:
	_toggle.text = "%s  %s  ·  %s" % ["▾" if _body.visible else "▸", _title, summary()]
	var p: PackedStringArray = problems()
	_problems.text = ("Fix: " + "; ".join(p)) if not p.is_empty() else ""
	_problems.visible = not p.is_empty()


func _row(label: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_body.add_child(row)
	var l := Label.new()
	l.text = label
	l.theme_type_variation = &"Muted"
	l.custom_minimum_size = Vector2(110, 0)
	row.add_child(l)
	return row


func _picker(row: HBoxContainer) -> OptionButton:
	var o := OptionButton.new()
	o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	o.clip_text = true
	o.add_item(RANDOM_TEXT)
	o.set_item_metadata(0, Loadout.RANDOM)
	row.add_child(o)
	return o


static func _select_id(o: OptionButton, id: String) -> void:
	for i: int in o.item_count:
		if str(o.get_item_metadata(i)) == id:
			o.select(i)
			return
	o.select(0)
