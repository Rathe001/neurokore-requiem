extends Node

# Session perf logger. Samples performance counters once per second
# and writes them to user://perf_log.csv. Also tags discrete game
# events (level-up, level-load, fire_lmb, aggro_cascade, etc.) as
# event rows so spike correlation is straightforward when reading
# the CSV back.
#
# Format:
#   time_s, fps, frame_ms, proc_ms, phys_ms,
#   enemies, enemies_active, enemies_chasing, enemies_combat,
#   weapon_id, firing, player_x, player_z,
#   projectiles, decals, casings,
#   draws, tris, objects,
#   lights_visible, lights_total, mmi_visible, particles_visible,
#   total_nodes, event
#
# Column groups, in order:
#   - Frame timing            (time, fps, frame/proc/phys ms)
#   - Enemy subsystem         (total / actively ticking / chasing / in-combat)
#   - Player action context   (current weapon, holding fire, world pos)
#   - Transient counts        (live projectiles / decals / shell casings)
#   - Render counts           (draws, tris, objects)
#   - Tree walks              (light/mmi/particles visible — expensive,
#                              skipped on spike rows to break feedback loop)
#   - event                   ("" for periodic, populated for tagged events)
#
# Output file flushes every sample so a crash mid-session doesn't
# lose the data. File is at user://perf_log.csv — on Windows that's
# %APPDATA%\Godot\app_userdata\Neurokore Requiem\perf_log.csv. The
# autoload opens with WRITE mode at session start so each playthrough
# overwrites the previous log (rename in-place if you want to keep
# multiple).

const SAMPLE_INTERVAL: float = 1.0
const LOG_PATH: String = "user://perf_log.csv"
# Spike detection: when proc OR phys exceed this threshold on the
# 1Hz periodic sample, ALSO write a "spike_detected" tagged event
# row so the CSV reader can find the moment easily. Threshold is
# generous (50ms) so we only flag actual visible hitches.
const SPIKE_THRESHOLD_MS: float = 50.0
# Minimum interval between spike rows. WITHOUT this, sustained slowdowns
# fire a spike row every frame, and each row's tree-walk cost (~20-30ms)
# adds back to TIME_PROCESS on the next frame — a positive feedback loop
# that keeps the system in spike mode forever. Throttling to 5/sec means
# the logger contributes at most ~150ms/sec of its own overhead during
# sustained spikes instead of 60×30=1800ms/sec.
const SPIKE_MIN_INTERVAL_SEC: float = 0.2

# State enum values mirrored from PrototypeEnemy.State so we don't have
# to load the class here. Update if the enum ever changes; otherwise the
# enemies_chasing / enemies_combat columns will silently mis-count.
const _STATE_CHASING: int = 1
const _STATE_CASTING: int = 6
const _STATE_ATTACKING: int = 7
const _STATE_JUMPING: int = 5

# fire_lmb event throttle. _cast_lmb_combat is called every frame the
# button is held, but we only want one event per burst — otherwise a
# 5-second laser-pistol hold floods the CSV with 300 fire_lmb rows.
# Re-tag if a tag was suppressed and the player has now released and
# pressed again (gap > LMB_TAG_GAP_SEC).
const LMB_TAG_GAP_SEC: float = 0.5
var _last_lmb_tag_t: float = -1000.0

var _file: FileAccess
var _accum: float = 0.0
var _spike_accum: float = 0.0
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
	_spike_accum += delta
	# Check every frame for spike threshold, not just at 1Hz cadence.
	# A 300ms freeze between 1Hz samples would otherwise show up in
	# the AFTER sample, smoothed over. Sampling per-frame lets us
	# catch the exact spike frame. To avoid flooding the CSV with
	# 60 rows/sec of normal data, we only WRITE when either a spike
	# fires or 1s has elapsed since the last sample. Spike writes are
	# additionally throttled to SPIKE_MIN_INTERVAL_SEC so the logger
	# can't feedback-loop itself into permanent spike mode.
	var proc_ms: float = Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var phys_ms: float = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	var spike := proc_ms > SPIKE_THRESHOLD_MS or phys_ms > SPIKE_THRESHOLD_MS
	if spike and _spike_accum >= SPIKE_MIN_INTERVAL_SEC:
		_accum = 0.0
		_spike_accum = 0.0
		var which: StringName = &"spike_proc" if proc_ms > phys_ms else &"spike_phys"
		# Spike rows skip the expensive tree walks (they were adding
		# 20-30ms of feedback overhead per frame). Periodic 1Hz rows
		# also skip them now (see below); only explicit event tags pay
		# the full cost.
		_write_row(which, true)
		return
	if _accum < SAMPLE_INTERVAL:
		return
	_accum = 0.0
	# Periodic 1Hz samples skip the tree walks too. At ~9000 nodes those
	# walks cost ~20-30ms each, producing a recurring once-per-second
	# stutter that was big enough to read as a perf issue on top of the
	# real spikes we're trying to diagnose. The walks still run on
	# explicit event tags (build_end, level_up, aggro_cascade, fire_lmb)
	# so post-event snapshots stay accurate — that's where you'd
	# actually want to know how many lights or particle systems were
	# live anyway.
	_write_row(&"", true)


# ── Public API ──────────────────────────────────────────────────────────────

## Tag a one-shot event row with the current perf snapshot. Use for
## anything you want to correlate against the spike chart later —
## level-up, level-load, big explosion, manual marker on a key press.
## Event rows DO pay the full tree-walk cost so post-event analysis can
## see what the world looked like at that moment.
## Tag an event row. By default skips the tree walks (lights/MMI/
## particles columns will be 0 on the row) because at ~11000 nodes
## the three full find_children walks cost 15-30ms each and turn
## every event tag into a perceptible hitch. Pass `with_snapshot=true`
## for the handful of events where the snapshot is the whole point
## (build_start, build_end, level_up) — those are infrequent enough
## that the cost is acceptable.
func tag_event(event_name: StringName, with_snapshot: bool = false) -> void:
	if _file == null:
		return
	_write_row(event_name, not with_snapshot)


## Specialised LMB-fire tag. Throttled to LMB_TAG_GAP_SEC because
## _cast_lmb_combat fires every frame the button is held — without
## this, a long laser-pistol burst would flood the CSV with hundreds
## of fire_lmb rows. The first fire of a burst gets tagged; subsequent
## frames within the gap window are suppressed; releasing for >gap
## seconds re-arms the next press.
##
## Always skips tree walks. The CSV at t=30-33 caught this: every
## fire_lmb event was triggering ~15-30ms of tree-walk work in addition
## to the actual shot, producing the per-shot proc spikes we'd been
## chasing through the hitscan VFX path. The walks aren't useful at
## fire moments (the world state doesn't materially change shot-to-shot
## from a lighting/MMI perspective), so always-skip is fine.
func tag_fire_lmb() -> void:
	if _file == null:
		return
	var now: float = float(Time.get_ticks_msec() - _session_start_msec) / 1000.0
	if now - _last_lmb_tag_t < LMB_TAG_GAP_SEC:
		return
	_last_lmb_tag_t = now
	_write_row(&"fire_lmb", true)


# ── Internals ───────────────────────────────────────────────────────────────

func _open_log() -> void:
	_file = FileAccess.open(LOG_PATH, FileAccess.WRITE)
	if _file == null:
		push_warning("[PerfLogger] failed to open %s for write (err %d)" % [LOG_PATH, FileAccess.get_open_error()])
		set_process(false)
		return
	# Header row — keep in sync with _write_row's column order.
	_file.store_line("time_s,fps,frame_ms,proc_ms,phys_ms,enemies,enemies_active,enemies_chasing,enemies_combat,weapon_id,firing,player_x,player_z,projectiles,decals,casings,corpses,jolt_bodies,jolt_pairs,jolt_islands,draws,tris,objects,lights_visible,lights_total,mmi_visible,particles_visible,total_nodes,event")


## `skip_tree_walks` — when true, the per-write tree enumeration
## (find_children for Light3D / MultiMeshInstance3D / GPUParticles3D)
## is skipped and those columns log 0. Spike rows pass true because
## those tree walks at 6654 nodes cost 20-30ms each and would feedback
## into the next frame's TIME_PROCESS measurement, locking the logger
## into permanent spike mode. Periodic 1Hz samples and event tags pass
## false so the long-run trend captures real enumeration data.
func _write_row(event_name: StringName, skip_tree_walks: bool = false) -> void:
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
	var tree := get_tree()
	var total_nodes: int = tree.get_node_count() if tree != null else 0

	# Enemy state breakdown. One pass over the &"enemies" group counts
	# total + active (is_physics_processing) + per-state buckets. Cheap
	# even at horde density — group lookup is O(1), iteration is O(N).
	# Buckets:
	#   enemies         — every member of the group (alive or dying)
	#   enemies_active  — is_physics_processing()==true (i.e. NOT paused
	#                     by _update_physics_process_active). Direct read
	#                     of whether the pause optimisation is working.
	#   enemies_chasing — state == CHASING (the dominant cost driver when
	#                     it isn't paused, e.g. visible pursuers).
	#   enemies_combat  — state in {CASTING, ATTACKING, JUMPING} — active
	#                     combat states that are exempt from the pause
	#                     and run at full 60Hz, so they represent the
	#                     irreducible per-frame floor.
	var enemies: int = 0
	var enemies_active: int = 0
	var enemies_chasing: int = 0
	var enemies_combat: int = 0
	if tree != null:
		for e: Node in tree.get_nodes_in_group(&"enemies"):
			if not is_instance_valid(e):
				continue
			enemies += 1
			if e is Node3D and (e as Node3D).is_physics_processing():
				enemies_active += 1
			if "_state" in e:
				var st: int = e.get(&"_state")
				if st == _STATE_CHASING:
					enemies_chasing += 1
				elif st == _STATE_CASTING or st == _STATE_ATTACKING or st == _STATE_JUMPING:
					enemies_combat += 1

	# Player action context. Empty/zero when no local player (intro
	# scene, between deaths, etc.).
	var weapon_id: String = ""
	var firing: int = 0
	var player_x: float = 0.0
	var player_z: float = 0.0
	if tree != null:
		var player := tree.get_first_node_in_group(&"player") as Node3D
		if player != null:
			player_x = player.global_position.x
			player_z = player.global_position.z
			if InventoryState != null:
				var w: Item = InventoryState.get_equipped(&"weapon")
				if w != null:
					weapon_id = String(w.weapon_base_id)
			# is_action_pressed works for any peer's input on the
			# host's machine; correlates "spike during firing" cleanly.
			if InputMap.has_action(&"fire") and Input.is_action_pressed(&"fire"):
				firing = 1

	# Transient node counts. Projectiles + shell casings are joined to
	# their respective groups on _ready (group adds are cheap, and
	# Godot auto-removes on queue_free). Decals are tracked by the
	# attack indicator's static ring arrays — read them directly.
	# Corpses are tracked via the &"ragdoll_corpses" group joined in
	# PrototypeEnemy._die (skel-with-XBotRagdoll, anim-only, AND legacy
	# capsule paths all add to the group). Includes both the per-bone
	# PhysicalBone3D rigs AND the death-anim-then-sink corpses, so a
	# rising number tells us deaths are accumulating regardless of
	# which death path triggered.
	var projectiles: int = 0
	var casings: int = 0
	var corpses: int = 0
	if tree != null:
		projectiles = tree.get_nodes_in_group(&"projectiles").size()
		casings = tree.get_nodes_in_group(&"shell_casings").size()
		corpses = tree.get_nodes_in_group(&"ragdoll_corpses").size()
	var decals: int = PrototypeAttackIndicator._blood_decal_ring.size() + PrototypeAttackIndicator._wall_impact_ring.size()

	# Jolt physics engine counters. The script-side counters above
	# (enemies_active / projectiles / casings / corpses) report what
	# OUR code is doing; these report what JOLT is doing. Useful when
	# phys_ms spikes with all of our counters at zero — means the cost
	# is in the physics engine itself (broad-phase, narrow-phase, island
	# solving) rather than in our _physics_process callbacks.
	#   jolt_bodies  — active rigid bodies (excludes sleeping)
	#   jolt_pairs   — broad-phase collision pairs being evaluated
	#   jolt_islands — solver islands (clusters of touching bodies)
	# Available via Performance enum since Godot 4.x; return 0 on
	# rendering-only backends or non-Jolt physics.
	var jolt_bodies: int = int(Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS))
	var jolt_pairs: int = int(Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS))
	var jolt_islands: int = int(Performance.get_monitor(Performance.PHYSICS_3D_ISLAND_COUNT))

	var lights_visible: int = 0
	var lights_total: int = 0
	var mmi_visible: int = 0
	var particles_visible: int = 0
	# Expensive: full-tree find_children walks. Skipped on spike rows
	# to break the perf-logger feedback loop (writes adding to the
	# next frame's measured proc time, perpetuating the spike).
	if tree != null and not skip_tree_walks:
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
	_file.store_line("%.2f,%d,%.2f,%.2f,%.2f,%d,%d,%d,%d,%s,%d,%.1f,%.1f,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%s" % [
		t_s, fps, frame_ms, proc_ms, phys_ms,
		enemies, enemies_active, enemies_chasing, enemies_combat,
		weapon_id, firing, player_x, player_z,
		projectiles, decals, casings, corpses,
		jolt_bodies, jolt_pairs, jolt_islands,
		draws, tris, objects,
		lights_visible, lights_total,
		mmi_visible, particles_visible,
		total_nodes,
		String(event_name),
	])
	# Flush so a crash mid-session doesn't lose the data.
	_file.flush()


func _on_leveled_up(new_level: int, _hp_gain: int) -> void:
	tag_event(StringName("level_up_%d" % new_level), true)  # rare event, snapshot is useful
