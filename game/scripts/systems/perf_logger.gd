extends Node

# Session perf logger. Samples performance counters once per second
# and writes them to user://perf_log.csv. Also tags discrete game
# events (level-up, level-load, etc.) as event rows so spike
# correlation is straightforward when reading the CSV back.
#
# Format:
#   time_s, fps, frame_ms, proc_ms, phys_ms, enemies, draws, tris,
#   objects, lights_visible, lights_total, mmi_visible, particles_visible,
#   total_nodes, event
#
# Event column is empty for periodic samples, populated for tagged
# events (e.g. "level_up", "level_load", "explosion"). The same row
# layout for both lets a CSV viewer / spreadsheet line them up
# directly against the timeline.
#
# Output file flushes every sample so a crash mid-session doesn't
# lose the data. File is at user://perf_log.csv — on Windows that's
# %APPDATA%\Godot\app_userdata\Neurokore Requiem\perf_log.csv. The
# autoload deletes the existing file at session start so each playthrough
# gets a clean log (rename in-place if you want to keep multiple).

const SAMPLE_INTERVAL: float = 1.0
const LOG_PATH: String = "user://perf_log.csv"

var _file: FileAccess
var _accum: float = 0.0
var _session_start_msec: int = 0


func _ready() -> void:
	# Disable in non-debug builds — Performance counters return 0 in
	# release. Also keeps the disk write out of shipping builds.
	if not OS.is_debug_build():
		print("[PerfLogger] disabled (non-debug build).")
		set_process(false)
		return
	_session_start_msec = Time.get_ticks_msec()
	_open_log()
	# Echo the resolved absolute path so the user can find the file
	# without having to guess where Godot's user:// resolves on their
	# OS. ProjectSettings.globalize_path("user://") returns the actual
	# filesystem path.
	var abs_path: String = ProjectSettings.globalize_path(LOG_PATH)
	print("[PerfLogger] writing to: %s" % abs_path)
	# Hook the level-up signal so we get an event marker exactly when
	# the spike happens. PlayerState is an autoload so its signal is
	# always reachable.
	if Engine.has_singleton("PlayerState") or PlayerState != null:
		PlayerState.leveled_up.connect(_on_leveled_up)


func _exit_tree() -> void:
	if _file != null:
		_file.close()
		_file = null


func _process(delta: float) -> void:
	_accum += delta
	if _accum < SAMPLE_INTERVAL:
		return
	_accum = 0.0
	_write_row(&"")


# ── Public API ──────────────────────────────────────────────────────────────

## Tag a one-shot event row with the current perf snapshot. Use for
## anything you want to correlate against the spike chart later —
## level-up, level-load, big explosion, manual marker on a key press.
func tag_event(event_name: StringName) -> void:
	if _file == null:
		return
	_write_row(event_name)


# ── Internals ───────────────────────────────────────────────────────────────

func _open_log() -> void:
	_file = FileAccess.open(LOG_PATH, FileAccess.WRITE)
	if _file == null:
		push_warning("[PerfLogger] failed to open %s for write (err %d)" % [LOG_PATH, FileAccess.get_open_error()])
		set_process(false)
		return
	# Header row — keep in sync with _write_row's column order.
	_file.store_line("time_s,fps,frame_ms,proc_ms,phys_ms,enemies,draws,tris,objects,lights_visible,lights_total,mmi_visible,particles_visible,total_nodes,event")


func _write_row(event_name: StringName) -> void:
	if _file == null:
		return
	var t_s: float = float(Time.get_ticks_msec() - _session_start_msec) / 1000.0
	var fps: int = Engine.get_frames_per_second()
	var frame_ms: float = 1000.0 / maxf(float(fps), 1.0)
	var proc_ms: float = Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var phys_ms: float = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	var draws: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var tris: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	var objects: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
	# Counts that need a tree walk — cheap at 1Hz, free at sub-Hz.
	var tree := get_tree()
	var enemies: int = SpatialGrid.count(&"enemies") if SpatialGrid != null else 0
	var total_nodes: int = tree.get_node_count() if tree != null else 0
	var lights_visible: int = 0
	var lights_total: int = 0
	var mmi_visible: int = 0
	var particles_visible: int = 0
	if tree != null:
		for n in tree.get_root().find_children("*", "Light3D", true, false):
			var light := n as Light3D
			if light == null:
				continue
			lights_total += 1
			if light.is_visible_in_tree():
				lights_visible += 1
		for n in tree.get_root().find_children("*", "MultiMeshInstance3D", true, false):
			if (n as MultiMeshInstance3D).is_visible_in_tree():
				mmi_visible += 1
		for n in tree.get_root().find_children("*", "GPUParticles3D", true, false):
			if (n as GPUParticles3D).is_visible_in_tree():
				particles_visible += 1
	# Compact column order — matches header above.
	_file.store_line("%.2f,%d,%.2f,%.2f,%.2f,%d,%d,%d,%d,%d,%d,%d,%d,%d,%s" % [
		t_s, fps, frame_ms, proc_ms, phys_ms,
		enemies, draws, tris, objects,
		lights_visible, lights_total,
		mmi_visible, particles_visible,
		total_nodes,
		String(event_name),
	])
	# Flush so a crash mid-session doesn't lose the data.
	_file.flush()


func _on_leveled_up(new_level: int, _hp_gain: int) -> void:
	tag_event(StringName("level_up_%d" % new_level))
