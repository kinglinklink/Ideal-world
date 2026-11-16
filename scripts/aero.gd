extends RefCounted
## The air: how thick it is, and what it does to a flat aero panel.
## Used by Spawn for the real forces and by build mode for the centre of
## lift marker, so the two can never disagree.

const MapInfo = preload("res://scripts/map_info.gd")

const SEA_LEVEL_AIR := 1.225       # kg/m^3
const AIR_SCALE_HEIGHT := 8500.0   # metres; air density falls by e over this height
const STALL_ANGLE := 15.0          # degrees
const STALL_BLEND := 2.0           # degrees either side of stall over which the lift curves are blended


## Air density in kg/m^3 at a height in game metres (above the build pad).
## It thins with real altitude above sea level, which gives wings a natural
## ceiling: the pad on Wild Horse Island is about 900 m up already.
static func air_density(height: float) -> float:
	return SEA_LEVEL_AIR * exp(-maxf(height + MapInfo.BASE_ELEVATION, 0.0) / AIR_SCALE_HEIGHT)


## The lift coefficient of a flat panel at an angle of attack in radians.
## Below stall lift rises steadily, 4.0 per radian. Past stall it follows a
## flat plate, sin(2 x angle). The two are blended around the stall angle.
static func lift_coefficient(angle: float) -> float:
	var attached: float = 4.0 * angle
	var stalled: float = sin(2.0 * angle)
	var blend: float = smoothstep(deg_to_rad(STALL_ANGLE - STALL_BLEND),
			deg_to_rad(STALL_ANGLE + STALL_BLEND), angle)
	return lerpf(attached, stalled, blend)


## The force of the air on one flat panel, in newtons.
##
## `moving` is the panel's velocity through still air, `normal` the direction
## its flat faces look along, `area` its area in m^2 and `density` the air
## density. From the angle of attack:
##   lift = 1/2 x density x speed^2 x area x lift coefficient
##   drag = 1/2 x density x speed^2 x area x (0.01 + 2 sin^2 angle)
## Lift acts at right angles to the airflow, pushing the panel away from the
## face the air strikes, and drag acts along the airflow. A dragless panel
## makes the lift and no drag at all.
static func panel_force(moving: Vector3, normal: Vector3, area: float, dragless: bool, density: float) -> Vector3:
	var speed: float = moving.length()
	if speed < 0.05:
		return Vector3.ZERO
	var heading: Vector3 = moving / speed
	# How squarely the panel meets the air: the sine of the angle of attack.
	# Its sign says which face the air strikes.
	var facing: float = heading.dot(normal)
	var sine: float = minf(absf(facing), 1.0)
	var angle: float = asin(sine)
	var pressure: float = 0.5 * density * speed * speed * area
	var force := Vector3.ZERO
	if not dragless:
		force = -heading * (pressure * (0.01 + 2.0 * sine * sine))
	var across: Vector3 = normal - heading * facing
	if across.length() > 0.0001:
		force += across.normalized() * (-signf(facing) * pressure * lift_coefficient(angle))
	return force
