extends CanvasLayer

var label_left: Label = null
var _player_label: Label = null
var _menu_button: Button = null
var _settings_panel: PanelContainer = null
var _settings_vbox: VBoxContainer = null

func _ready() -> void:
	layer = 55
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
	label_left.add_theme_font_size_override("font_size", 16)
	label_left.add_theme_color_override("font_color", Color.WHITE)
	add_child(label_left)

	var right_box := HBoxContainer.new()
	right_box.name = "TopBarRight"
	right_box.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	right_box.offset_left = -320.0
	right_box.offset_top = 4.0
	right_box.offset_right = -10.0
	right_box.offset_bottom = 32.0
	right_box.add_theme_constant_override("separation", 12)
	right_box.alignment = BoxContainer.ALIGNMENT_END
	add_child(right_box)

	_player_label = Label.new()
	_player_label.name = "TopBarLabelRight"
	_player_label.add_theme_font_size_override("font_size", 18)
	_player_label.add_theme_color_override("font_color", Color.WHITE)
	right_box.add_child(_player_label)

	_menu_button = Button.new()
	_menu_button.name = "MenuButton"
	_menu_button.text = "Menu"
	_menu_button.focus_mode = Control.FOCUS_NONE
	_menu_button.pressed.connect(_on_menu_pressed)
	right_box.add_child(_menu_button)

	_settings_panel = PanelContainer.new()
	_settings_panel.name = "SettingsPanel"
	_settings_panel.visible = false
	_settings_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_settings_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_settings_panel.offset_left = -320.0
	_settings_panel.offset_top = 38.0
	_settings_panel.offset_right = -10.0
	_settings_panel.offset_bottom = 420.0
	add_child(_settings_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 8)
	_settings_panel.add_child(margin)

	_settings_vbox = VBoxContainer.new()
	_settings_vbox.add_theme_constant_override("separation", 8)
	margin.add_child(_settings_vbox)

	label_left.move_to_front()
	right_box.move_to_front()

func settings_vbox() -> VBoxContainer:
	return _settings_vbox

func _on_menu_pressed() -> void:
	if _settings_panel != null:
		_settings_panel.visible = not _settings_panel.visible

func update_display(
	stables_count: int,
	blacksmith_count: int,
	village_count: int,
	archery_count: int,
	horses: int,
	spears: int,
	bows: int,
	villagers: int,
	player_name: String,
	player_color: Color = Color.WHITE,
) -> void:
	if label_left:
		label_left.text = (
			"Stab:%d Blk:%d Vill:%d Arch:%d  H:%d S:%d B:%d V:%d"
			% [stables_count, blacksmith_count, village_count, archery_count, horses, spears, bows, villagers]
		)
	if _player_label:
		_player_label.text = "Player: %s" % player_name
		_player_label.add_theme_color_override("font_color", player_color)
