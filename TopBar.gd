extends CanvasLayer

var label_left: Label = null
var label_right: Label = null

func _ready():
	var bg = ColorRect.new()
	bg.name = "TopBarBG"
	bg.offset_left = 0
	bg.offset_top = 0
	bg.offset_right = 1280
	bg.offset_bottom = 35
	bg.color = Color(0.0, 0.0, 0.0, 0.6)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.show_behind_parent = true
	add_child(bg)

	label_left = Label.new()
	label_left.name = "TopBarLabelLeft"
	label_left.offset_left = 10
	label_left.offset_top = 5
	label_left.offset_right = 900
	label_left.offset_bottom = 30
	label_left.add_theme_font_size_override("font_size", 18)
	label_left.add_theme_color_override("font_color", Color.WHITE)
	add_child(label_left)

	label_right = Label.new()
	label_right.name = "TopBarLabelRight"
	label_right.offset_left = 950
	label_right.offset_top = 5
	label_right.offset_right = 1270
	label_right.offset_bottom = 30
	label_right.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label_right.add_theme_font_size_override("font_size", 18)
	label_right.add_theme_color_override("font_color", Color.WHITE)
	add_child(label_right)

	bg.move_to_back()
	label_left.move_to_front()
	label_right.move_to_front()

func update_display(stables_count: int, blacksmith_count: int, horses: int, spears: int, player_name: String):
	if label_left:
		label_left.text = "Stables: %d  Blacksmith: %d  Horses: %d  Spears: %d" % [stables_count, blacksmith_count, horses, spears]
	if label_right:
		label_right.text = "Player: %s" % player_name
