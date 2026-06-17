extends PanelContainer

@onready var _music_slider: HSlider = $Margin/VBox/MusicRow/MusicSlider
@onready var _sfx_slider: HSlider = $Margin/VBox/SfxRow/SfxSlider

var _syncing_sliders := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_music_slider.mouse_filter = Control.MOUSE_FILTER_STOP
	_sfx_slider.mouse_filter = Control.MOUSE_FILTER_STOP

	_music_slider.min_value = 0.0
	_music_slider.max_value = 100.0
	_music_slider.step = 1.0
	_sfx_slider.min_value = 0.0
	_sfx_slider.max_value = 100.0
	_sfx_slider.step = 1.0

	_syncing_sliders = true
	_music_slider.value = AudioSettings.get_music_volume_linear() * 100.0
	_sfx_slider.value = AudioSettings.get_sfx_volume_linear() * 100.0
	_syncing_sliders = false

	_music_slider.value_changed.connect(_on_music_changed)
	_sfx_slider.value_changed.connect(_on_sfx_changed)

func _on_music_changed(value: float) -> void:
	if _syncing_sliders:
		return
	AudioSettings.set_music_volume_linear(value / 100.0)

func _on_sfx_changed(value: float) -> void:
	if _syncing_sliders:
		return
	AudioSettings.set_sfx_volume_linear(value / 100.0)
