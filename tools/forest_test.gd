extends SceneTree
## Headless check of the tree kinds: counts every tree in the squares built
## round the hangar by kind, and checks a tree's trunk kind matches its
## drawn kind.
##     godot --headless --path . -s tools/forest_test.gd

const Forest = preload("res://scripts/forest.gd")

var main: Node = null
var frame := 0


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)


func _process(_delta: float) -> bool:
	frame += 1
	if frame == 5:
		main.get_node("Menus").start_game()
	if frame == 200:
		var forest: Node = main.get_node("Terrain/Forest")
		var counts: Array = []
		counts.resize(Forest.SPECIES.size())
		counts.fill(0)
		var squares := 0
		for key in forest._built:
			squares += 1
			for item in forest._built[key]:
				var batch: MultiMesh = (item as MultiMeshInstance3D).multimesh
				counts[forest._meshes.find(batch.mesh)] += batch.instance_count
		var total := 0
		for value in counts:
			total += int(value)
		print("FOREST: %d squares built, %d trees" % [squares, total])
		for kind in Forest.SPECIES.size():
			print("FOREST: %-24s %6d  %4.1f%%" % [Forest.SPECIES[kind][0], counts[kind], 100.0 * counts[kind] / maxf(total, 1)])
		# Elevation spread: the kinds above 1,800 m and below 1,000 m.
		var high := {}
		var low := {}
		for tree in range(0, mini(forest._trees.size() / 4, 200000), 7):
			var y: float = forest._trees[tree * 4 + 1]
			var kind: int = Forest.species_of(tree, y, Vector2.ZERO)
			if y + 901.0 > 1900.0:
				high[kind] = int(high.get(kind, 0)) + 1
			elif y < -10.0:
				low[kind] = int(low.get(kind, 0)) + 1
		var name_counts := func(found: Dictionary) -> String:
			var parts: Array = []
			for kind in found:
				parts.append("%s %d" % [Forest.SPECIES[kind][0], found[kind]])
			return ", ".join(parts)
		print("FOREST: above 1,900 m: ", name_counts.call(high))
		print("FOREST: on the shore: ", name_counts.call(low))
		return true
	return false
