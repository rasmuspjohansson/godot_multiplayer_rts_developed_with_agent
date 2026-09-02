extends Control
## Order mode + stance controls for selected armies (client UI).

signal order_mode_changed(mode: int)
signal stance_pressed(stance: int)

enum OrderMode { MOVE, ATTACK, ATTACK_MOVE }

var _order_buttons: Array[Button] = []
var _stance_buttons: Array[Button] = []
var _order_mode: int = OrderMode.MOVE

const ORDER_LABELS := ["Move", "Attack", "Attack-Move"]
const STANCE_LABELS := ["Aggressive", "Defensive", "Hold", "Passive"]

func _ready() -> void:
	visible = false
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var order_row := HBoxContainer.new()
	root.add_child(order_row)
	for i in range(ORDER_LABELS.size()):
		var btn := Button.new()
		btn.text = ORDER_LABELS[i]
		btn.toggle_mode = true
		btn.button_pressed = i == OrderMode.MOVE
		var mode := i
		btn.pressed.connect(func(): _set_order_mode(mode))
		order_row.add_child(btn)
		_order_buttons.append(btn)
	var stance_row := HBoxContainer.new()
	root.add_child(stance_row)
	for i in range(STANCE_LABELS.size()):
		var btn := Button.new()
		btn.text = STANCE_LABELS[i]
		var stance := i
		btn.pressed.connect(func(): stance_pressed.emit(stance))
		stance_row.add_child(btn)
		_stance_buttons.append(btn)

func get_order_mode() -> int:
	return _order_mode

func _set_order_mode(mode: int) -> void:
	_order_mode = mode
	for i in range(_order_buttons.size()):
		_order_buttons[i].button_pressed = i == mode
	order_mode_changed.emit(mode)

func set_visible_bar(show_bar: bool) -> void:
	visible = show_bar
