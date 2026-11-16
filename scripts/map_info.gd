extends RefCounted
## Written by tools/bake_map.py. Do not edit by hand: run the script again.
##
## Where the map's data sits in game coordinates. The origin is the corner of
## the build pad on Wild Horse Island, east is +X, north is -Z, and Y = 0 is
## the level of the pad.

const BASE_ELEVATION := 901.00   ## metres above sea level of Y = 0
const LAKE_Y := -20.40           ## the lake surface

const COARSE_FILE := "res://map_data/terrain_coarse.png"
const COARSE_ORIGIN := Vector2(-25664.0, -34912.0)   ## X and Z of the first sample
const COARSE_SPACING := 16.0
const COARSE_SIZE := Vector2i(3893, 4096)
const COARSE_SCALE := 20.0    ## height = value / scale - offset
const COARSE_OFFSET := 300.0

const DETAIL_FILE := "res://map_data/terrain_detail.png"
const DETAIL_ORIGIN := Vector2(-7636.0, -3872.0)
const DETAIL_SPACING := 4.0
const DETAIL_SIZE := Vector2i(3074, 2458)
const DETAIL_SCALE := 100.0
const DETAIL_OFFSET := 200.0

const TILE := 128.0    ## collision squares, metres
const CELL := 1024.0    ## tree drawing squares, metres
const WORLD_FILE := "res://map_data/world.json"
const TREES_FILE := "res://map_data/trees.bin"
const TREE_TILES_FILE := "res://map_data/tree_tiles.bin"
const MINIMAP_FILE := "res://map_data/minimap.png"
