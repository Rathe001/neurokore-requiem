class_name WeaponMeterStrip
extends Control

# Container that owns N StatMeterBar children — one per bar in the weapon's
# meter set. The tooltip creates one instance and calls populate() each time
# a new weapon is hovered. Bars are recycled (hidden/shown) rather than
# freed/recreated to avoid GC churn during rapid hover switches.

var _bars: Array[StatMeterBar] = []
const MAX_BARS := 9  # Up to 5 standard bars + up to 2 signature bars + margin


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
	for i in MAX_BARS:
		if i < count:
			var data: WeaponMeterData.MeterBar = meter_data[i]
			var bar: StatMeterBar = _bars[i]
			bar.label_text = data.label
			bar.value = data.value
			bar.decayed_value = data.decayed_value
			bar.boosted_value = data.boosted_value
			bar.number_text = data.number_text
			bar.position = Vector2(0, float(i) * StatMeterBar.ROW_HEIGHT)
			bar.visible = true
			bar.update_pulse()
			bar.queue_redraw()
		else:
			_bars[i].visible = false
			_bars[i].set_process(false)
	custom_minimum_size = Vector2(
		StatMeterBar.TOTAL_WIDTH,
		float(count) * StatMeterBar.ROW_HEIGHT
	)


func update_theme() -> void:
	for bar: StatMeterBar in _bars:
		bar.update_theme()
