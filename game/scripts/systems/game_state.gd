extends Node

signal switch_changed(id: String, value: bool)

var _switches: Dictionary = {}

func set_switch(id: String, value: bool) -> void:
	if id == "":
		return
	var old_value: bool = _switches.get(id, false)
	if old_value == value:
		return
	_switches[id] = value
	switch_changed.emit(id, value)

func is_switch_on(id: String) -> bool:
	return _switches.get(id, false)
