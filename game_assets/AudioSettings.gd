extends Node
## Global music / SFX bus volumes with persistence.

const CONFIG_PATH := "user://audio_settings.cfg"
const BUS_MUSIC := "Music"
const BUS_SFX := "SFX"

var music_volume_linear := 0.35
var sfx_volume_linear := 0.9

func _ready() -> void:
	_load_settings()
	call_deferred("_apply_volumes")

func set_music_volume_linear(value: float) -> void:
	music_volume_linear = clampf(value, 0.0, 1.0)
	_apply_volumes()
	_save_settings()

func set_sfx_volume_linear(value: float) -> void:
	sfx_volume_linear = clampf(value, 0.0, 1.0)
	_apply_volumes()
	_save_settings()

func get_music_volume_linear() -> float:
	return music_volume_linear

func get_sfx_volume_linear() -> float:
	return sfx_volume_linear

func get_music_bus_name() -> StringName:
	return StringName(BUS_MUSIC)

func get_sfx_bus_name() -> StringName:
	return StringName(BUS_SFX)

func _apply_volumes() -> void:
	_set_bus_volume_linear(BUS_MUSIC, music_volume_linear)
	_set_bus_volume_linear(BUS_SFX, sfx_volume_linear)

func _set_bus_volume_linear(bus_name: String, linear_volume: float) -> void:
	var bus_idx := AudioServer.get_bus_index(bus_name)
	if bus_idx < 0:
		push_warning("AudioSettings: bus '%s' not found" % bus_name)
		return
	var db := -80.0 if linear_volume <= 0.0 else linear_to_db(linear_volume)
	AudioServer.set_bus_volume_db(bus_idx, db)

func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		return
	music_volume_linear = float(cfg.get_value("audio", "music_volume", music_volume_linear))
	sfx_volume_linear = float(cfg.get_value("audio", "sfx_volume", sfx_volume_linear))

func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "music_volume", music_volume_linear)
	cfg.set_value("audio", "sfx_volume", sfx_volume_linear)
	cfg.save(CONFIG_PATH)
