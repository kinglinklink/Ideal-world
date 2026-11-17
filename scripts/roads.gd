extends RefCounted
## The highway network, for traffic and car races: every paved motorway,
## trunk and primary road (towns.gd), joined end to end where they meet,
## and routes along it that keep going as straight as they can.

var lines: Array = []          # PackedVector3Array of map points per stretch
var _ends: Dictionary = {}     # Vector2i (half-metre grid) -> Array of [line index, true if it is the line's start]


func build(towns: Node) -> void:
	lines = towns.highway_lines()
	_ends.clear()
	for index in lines.size():
		var line: PackedVector3Array = lines[index]
		_file(_key(line[0]), [index, true])
		_file(_key(line[line.size() - 1]), [index, false])


static func _key(point: Vector3) -> Vector2i:
	return Vector2i(int(round(point.x * 2.0)), int(round(point.z * 2.0)))


func _file(key: Vector2i, entry: Array) -> void:
	if not _ends.has(key):
		_ends[key] = []
	(_ends[key] as Array).append(entry)


## The nearest highway point to a map position (x, z): [line, index], or
## empty if there are no highways.
func nearest(spot: Vector2) -> Array:
	var best := INF
	var found: Array = []
	for line_index in lines.size():
		var line: PackedVector3Array = lines[line_index]
		# A quick look at the ends and middle first, to skip far stretches.
		var middle := line[line.size() >> 1]
		if Vector2(middle.x, middle.z).distance_to(spot) - line.size() * 12.0 > best:
			continue
		for index in line.size():
			var distance := Vector2(line[index].x, line[index].z).distance_to(spot)
			if distance < best:
				best = distance
				found = [line_index, index]
	return found


## A route along the highways from a point on one, `length` metres long (or
## until the road ends), going `forward` along that stretch first. At each
## junction it takes the road that goes on straightest.
func route_from(line_index: int, start: int, forward: bool, length: float) -> PackedVector3Array:
	var route := PackedVector3Array()
	var travelled := 0.0
	var current := line_index
	var going := forward
	var index := start
	var visited: Dictionary = {}
	while travelled < length:
		var line: PackedVector3Array = lines[current]
		var step := 1 if going else -1
		while index >= 0 and index < line.size():
			if not route.is_empty():
				var gap := route[route.size() - 1].distance_to(line[index])
				if gap < 0.5:
					index += step
					continue
				travelled += gap
			route.append(line[index])
			if travelled >= length:
				return route
			index += step
		visited[current] = true
		# On to the next stretch at this end.
		var end_point := line[line.size() - 1] if going else line[0]
		var heading := Vector3.ZERO
		if route.size() >= 2:
			heading = (route[route.size() - 1] - route[route.size() - 2]).normalized()
		var best := -2.0
		var next_line := -1
		var next_forward := true
		for item in _ends.get(_key(end_point), []):
			var entry: Array = item
			var other: int = entry[0]
			if other == current or visited.has(other):
				continue
			var other_line: PackedVector3Array = lines[other]
			var starts: bool = entry[1]
			var first := other_line[0] if starts else other_line[other_line.size() - 1]
			var second := other_line[mini(1, other_line.size() - 1)] if starts else other_line[maxi(other_line.size() - 2, 0)]
			var way := (second - first).normalized()
			var straight := way.dot(heading)
			if straight > best:
				best = straight
				next_line = other
				next_forward = starts
		if next_line < 0 or best < -0.3:
			break
		current = next_line
		going = next_forward
		var next_points: PackedVector3Array = lines[current]
		index = 0 if going else next_points.size() - 1
	return route


## Distances along a route from its start, one per point.
static func distances(route: PackedVector3Array) -> PackedFloat32Array:
	var along := PackedFloat32Array()
	along.resize(route.size())
	var total := 0.0
	for index in route.size():
		if index > 0:
			total += route[index].distance_to(route[index - 1])
		along[index] = total
	return along


## The point and the direction a given distance along a route.
static func sample(route: PackedVector3Array, along: PackedFloat32Array, distance: float) -> Array:
	if route.size() < 2:
		return [route[0] if route.size() > 0 else Vector3.ZERO, Vector3.FORWARD]
	var low := 0
	var high := route.size() - 1
	distance = clampf(distance, 0.0, along[high])
	while high - low > 1:
		var middle := (low + high) >> 1
		if along[middle] <= distance:
			low = middle
		else:
			high = middle
	var span := maxf(along[high] - along[low], 0.001)
	var t := (distance - along[low]) / span
	var direction := (route[high] - route[low]).normalized()
	return [route[low].lerp(route[high], t), direction]
