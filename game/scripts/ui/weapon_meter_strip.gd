class_name WeaponMeterStrip
extends Control

# Container that owns N StatMeterBar children — one per bar in the weapon's
# meter set. The tooltip creates one instance and calls populate() each time
# a new weapon is hovered. Bars are recycled (hidden/shown) rather than
# freed/recreated to avoid GC churn during rapid hover switches.

var _bars: Array[StatMeterBar] = []
const MAX_BARS := 20  # Base bars + signature + affix modifier bars + comparison union


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	# Pre-allocate the maximum bar count. Unused bars stay hidden.
	for i in MAX_BARS:
		var bar := StatMeterBar.new()
		bar.mouse_filter = MOUSE_FILTER_IGNORE
		bar.visible = false
		add_child(bar)
		_bars.append(bar)


func populate(meter_data: Array[WeaponMeterData.MeterBar]) -> void:
	var count := mini(meter_data.size(), MAX_BARS)
	# Find the LAST global-flagged bar so the separator only renders once
	# at the transition between the global group and the archetype group,
	# even if multiple global bars exist in the future.
	var last_global := -1
	for i in count:
		if meter_data[i].is_global:
			last_global = i
	# Cumulative y so rows with extra-padding (separator-bearing) push
	# subsequent rows down by the right amount.
	var y := 0.0
	for i in MAX_BARS:
		if i < count:
			var data: WeaponMeterData.MeterBar = meter_data[i]
			var bar: StatMeterBar = _bars[i]
			bar.label_text = data.label
			bar.value = data.value
			bar.decayed_value = data.decayed_value
			bar.boosted_value = data.boosted_value
			bar.number_text = data.number_text
			bar.has_separator = (i == last_global)
			bar.position = Vector2(0, y)
			bar.visible = true
			bar.update_pulse()
			bar.queue_redraw()
			y += bar.row_height()
		else:
			_bars[i].visible = false
			_bars[i].set_process(false)
	custom_minimum_size = Vector2(StatMeterBar.TOTAL_WIDTH, y)


func update_theme() -> void:
	for bar: StatMeterBar in _bars:
		bar.update_theme()
