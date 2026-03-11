extends CanvasLayer

var label: Label = null

func _ready():
	label = Label.new()
	label.name = "TopBarLabel"
	label.offset_left = 10
	label.offset_top = 5
	label.offset_right = 700
	label.offset_bottom = 30
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color.WHITE)
	add_child(label)

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
	bg.move_to_front()
	label.move_to_front()

func update_display(resources: int, horses_owner: String, spears_owner: String):
	if label:
		label.text = "Resources: %d  |  Horses: %s  |  Spears: %s" % [resources, horses_owner, spears_owner]
