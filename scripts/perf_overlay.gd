extends CanvasLayer
## The performance overlay (F3): where each frame's time goes, in
## milliseconds per frame, by subsystem, with the heaviest line picked out
## and what in the build makes it heavy, so you can see which part of a
## machine causes the lag. Also counts what is in the scene.
##
## Jolt physics is the physics frames' time less the game's own physics
## work; drawing is the renderer's time on the CPU (and the GPU's where the
## driver reports it).

const Profiler = preload("res://scripts/profiler.gd")

const EVERY := 0.5                # seconds between updates
const ORDER := ["Jolt physics", "drivetrain", "fluids and engines", "aero and drag", "buoyancy", "logic",
		"stress", "weather and disasters", "traffic", "birds", "drawing"]
## The game's own work done inside the physics frames (taken off Jolt's share).
const IN_PHYSICS := ["drivetrain", "fluids and engines", "aero and drag", "buoyancy", "logic", "stress", "traffic"]

var spawner: Node = null          # spawner.gd
var engines: Node = null          # engines.gd
var _panel: PanelContainer
var _text: RichTextLabel
var _timer := 0.0
var _frames := 0
var _physics_seconds := 0.0       # physics frame time x ticks, summed since the last update
var _render_ms := 0.0
var _gpu_ms := 0.0


func _ready() -> void:
	layer = 60
	_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.06, 0.08, 0.82)
	style.set_corner_radius_all(6)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	_panel.add_theme_stylebox_override("panel", style)
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.offset_left = -330
	_panel.offset_right = -10
	_panel.offset_top = 60
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.fit_content = true
	_text.scroll_active = false
	_text.custom_minimum_size = Vector2(310, 0)
	_text.add_theme_font_size_override("normal_font_size", 13)
	_text.add_theme_font_size_override("mono_font_size", 13)
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_text)
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.physical_keycode == KEY_F3:
		toggle()


func toggle() -> void:
	visible = not visible
	Profiler.on = visible
	Profiler.take()
	var viewport := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(viewport, visible)
	_timer = 0.0
	_frames = 0
	_physics_seconds = 0.0
	_render_ms = 0.0
	_gpu_ms = 0.0
	if visible:
		_text.text = "Measuring..."


func _process(delta: float) -> void:
	if not visible:
		return
	_frames += 1
	_timer += delta
	_physics_seconds += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * Engine.physics_ticks_per_second * delta
	var viewport := get_viewport().get_viewport_rid()
	_render_ms += RenderingServer.viewport_get_measured_render_time_cpu(viewport) + RenderingServer.get_frame_setup_time_cpu()
	_gpu_ms += RenderingServer.viewport_get_measured_render_time_gpu(viewport)
	if _timer >= EVERY:
		_show(Profiler.take())
		_timer = 0.0
		_frames = 0
		_physics_seconds = 0.0
		_render_ms = 0.0
		_gpu_ms = 0.0


## Milliseconds per frame for each line, from the totals.
func lines_from(totals: Dictionary, frames: int, physics_ms: float, render_ms: float) -> Dictionary:
	var per_frame: Dictionary = {}
	var ours_in_physics := 0.0
	for subsystem in totals:
		var ms := float(totals[subsystem]) / 1000.0 / maxf(frames, 1)
		per_frame[subsystem] = ms
		if IN_PHYSICS.has(subsystem):
			ours_in_physics += ms
	per_frame["Jolt physics"] = maxf(physics_ms - ours_in_physics, 0.0)
	per_frame["drawing"] = render_ms
	return per_frame


func _show(totals: Dictionary) -> void:
	var frames := maxi(_frames, 1)
	var per_frame := lines_from(totals, frames, _physics_seconds * 1000.0 / frames, _render_ms / frames)
	var heaviest := ""
	var most := -1.0
	for subsystem in ORDER:
		if float(per_frame.get(subsystem, 0.0)) > most:
			most = float(per_frame.get(subsystem, 0.0))
			heaviest = subsystem
	var fps := Engine.get_frames_per_second()
	var lines: Array = ["[b]Performance[/b]  (F3)   %d fps, %.1f ms a frame" % [fps, 1000.0 / maxf(fps, 1.0)]]
	var table := "[table=2]"
	for subsystem in ORDER:
		var ms := float(per_frame.get(subsystem, 0.0))
		var colour := "#ffffff"
		if subsystem == heaviest and ms > 0.05:
			colour = "#ffb347"
		elif ms < 0.01:
			colour = "#888888"
		table += "[cell][color=%s]%s[/color][/cell][cell][right][color=%s]%.2f ms[/color][/right][/cell]" % [colour, subsystem, colour, ms]
	if _gpu_ms > 0.0:
		table += "[cell][color=#aaaaaa](GPU drawing)[/color][/cell][cell][right][color=#aaaaaa]%.2f ms[/color][/right][/cell]" % (_gpu_ms / frames)
	lines.append(table + "[/table]")
	var counts: Dictionary = spawner.counts() if spawner != null and bool(spawner.spawned) else {}
	var networks: int = engines.network_count() if engines != null and not counts.is_empty() else 0
	lines.append("Bodies %d   joints %d   parts %d   fluid networks %d" % [
			int(counts.get("bodies", 0)), int(counts.get("joints", 0)), int(counts.get("parts", 0)), networks])
	lines.append("Physics objects awake %d, collision pairs %d, draw calls %d" % [
			int(Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS)),
			int(Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS)),
			int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))])
	var why := cause(heaviest, counts, networks)
	if why != "":
		lines.append("[color=#ffb347]Heaviest: %s. %s[/color]" % [heaviest, why])
	_text.text = "\n".join(lines)


## What in the build is behind a subsystem's time, in words.
static func cause(subsystem: String, counts: Dictionary, networks: int) -> String:
	match subsystem:
		"Jolt physics":
			return "%d bodies and %d joints in your build; fewer, bigger welded bodies are cheaper." % [
					int(counts.get("bodies", 0)), int(counts.get("joints", 0))]
		"drivetrain":
			return "%d turning joints, %d sliders and %d gear meshes." % [int(counts.get("turning joints", 0)),
					int(counts.get("sliders", 0)), int(counts.get("gear meshes", 0))]
		"fluids and engines":
			return "%d fluid networks and %d thrusters." % [networks, int(counts.get("thrusters", 0))]
		"aero and drag":
			return "%d aero panels; merge small wings into bigger ones." % int(counts.get("aero panels", 0))
		"buoyancy":
			return "%d floating bodies." % int(counts.get("floating bodies", 0))
		"stress":
			return "the stress check over %d parts (cheaper with the stress view off)." % int(counts.get("parts", 0))
		"drawing":
			return "lower the view distance or shadows in Settings."
	return ""
