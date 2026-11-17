extends RefCounted
## The one place that fixes the game's scale. Change CELL to resize the grid.
##
## Sizes and positions are stored as whole numbers of "units". One unit is the
## smallest increment the build tools allow: 0.005 of a grid cell. Whole numbers
## never pick up rounding error, however often a part is moved or resized.

const CELL := 0.25                # metres per grid cell
const UNITS_PER_CELL := 200       # so one unit is 0.005 of a cell
const HALF_CELL_UNITS := 100
const UNIT := CELL / 200.0        # metres per unit

# Collision layers. The character looks for the world and for spawned bodies,
# but spawned bodies do not look for the character. That one-way arrangement
# means the physics engine never shoves a body out of the character's way
# with unlimited force: every push on a body comes from player.gd, in newtons.
const LAYER_WORLD := 1            # the ground, the garage, trees and parts on the build grid
const LAYER_PLAYER := 2
const LAYER_BODIES := 4           # spawned bodies


# Friction. Two surfaces in contact should grip by the geometric mean of
# their coefficients, √(μ1 × μ2). The physics engine instead takes the lower
# of the two. So every spawned body is given √μ of its own material, and the
# world's surfaces (taken as μ = 1) are given more than any body can have:
# against the world the engine then picks the body's √μ, which is exactly
# √(μ × 1). Between two bodies it picks the lower √μ, between the two rules.
const WORLD_FRICTION := 1.0       # the coefficient the world's surfaces stand for
static var _world_surface: PhysicsMaterial = null


## The surface every fixed part of the world uses (see above).
static func world_surface() -> PhysicsMaterial:
	if _world_surface == null:
		_world_surface = PhysicsMaterial.new()
		_world_surface.friction = 4.0   # above any body's √μ, so the engine takes the body's
		_world_surface.bounce = 0.0
	return _world_surface


## Converts a size or position in units to metres.
static func to_metres(units: Vector3i) -> Vector3:
	return Vector3(units) * UNIT
