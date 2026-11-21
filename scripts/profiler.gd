extends RefCounted
## Time spent in each of the game's subsystems, for the performance overlay
## (F3). Each subsystem adds the microseconds it took; the overlay reads the
## totals twice a second and clears them. Costs nothing while it is off.
##
##     var started := Profiler.start()
##     ... the work ...
##     Profiler.add("drivetrain", started)

static var on := false
static var totals: Dictionary = {}   # subsystem -> microseconds since the last read


static func start() -> int:
	return Time.get_ticks_usec() if on else 0


static func add(subsystem: String, started: int) -> void:
	if not on or started == 0:
		return
	totals[subsystem] = int(totals.get(subsystem, 0)) + Time.get_ticks_usec() - started


## The totals so far, and a fresh start.
static func take() -> Dictionary:
	var taken := totals
	totals = {}
	return taken
