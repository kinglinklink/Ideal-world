extends RefCounted
## Re-centring the world on the player.
##
## Godot works in 32-bit floats, which hold positions to about 1 mm at 16 km
## from the origin and 2 mm at 30 km: coarser than the 1.25 mm building step,
## and enough to make physics jitter at the far end of the lake. So whenever
## the player gets more than SHIFT_DISTANCE from the origin, main.gd moves the
## whole world back by a whole number of SHIFT_STEPs, keeping everything near
## the origin where floats are fine.
##
## "Map" positions are fixed to the ground (the pad's corner is always map
## 0, 0). "World" positions are what nodes use. They differ by `offset`:
##     map = world + offset
## Only X and Z shift; heights never do.

const SHIFT_DISTANCE := 1536.0   # metres from the origin before the world shifts
const SHIFT_STEP := 1024.0       # it shifts by whole multiples of this

static var offset := Vector3.ZERO


static func to_map(world: Vector3) -> Vector3:
	return world + offset


static func to_world(map: Vector3) -> Vector3:
	return map - offset
