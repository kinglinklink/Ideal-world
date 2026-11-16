"""Shared helpers for building Ideal World's map from map/terrain_*.png.

Ground positions use a flat map centred on a reference point near Wild Horse
Island: east is +X, north is -Z, in metres. Over the 60 km of the map the error
of this flat map is far smaller than the 13 m spacing of the elevation data.
"""

import json
import math
import os

import numpy as np
from PIL import Image
from scipy import ndimage

Image.MAX_IMAGE_PIXELS = None

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
MAP = os.path.join(ROOT, "map")

EARTH_RADIUS = 6371000.0
REF_LON = -114.215
REF_LAT = 47.845


def to_local(lon, lat):
    """Longitude and latitude to (x east, z south) metres from the reference point."""
    x = EARTH_RADIUS * math.cos(math.radians(REF_LAT)) * np.radians(np.asarray(lon) - REF_LON)
    z = -EARTH_RADIUS * np.radians(np.asarray(lat) - REF_LAT)
    return x, z


def to_lonlat(x, z):
    lon = REF_LON + np.degrees(np.asarray(x) / (EARTH_RADIUS * math.cos(math.radians(REF_LAT))))
    lat = REF_LAT - np.degrees(np.asarray(z) / EARTH_RADIUS)
    return lon, lat


def load_layer(name):
    """A downloaded layer: its heights in metres above sea level, and its placement."""
    info = json.load(open(os.path.join(MAP, "terrain.json")))
    layer = info["layers"][name]
    raw = np.asarray(Image.open(os.path.join(MAP, layer["file"]))).astype(np.float64)
    heights = info["base_height_m"] + raw / info["pixels_per_metre_of_height"]
    return heights, layer


def layer_pixels(layer, lon, lat):
    """Fractional (column, row) of points in a layer's image."""
    zoom = layer["zoom"]
    n = 2.0 ** zoom
    tx = (np.asarray(lon) + 180.0) / 360.0 * n
    lat_r = np.radians(np.asarray(lat))
    ty = (1.0 - np.log(np.tan(lat_r) + 1.0 / np.cos(lat_r)) / math.pi) / 2.0 * n
    # Pixel centres sit half a pixel in from the tile edges.
    return (tx - layer["tile_x"]) * 256.0 - 0.5, (ty - layer["tile_y"]) * 256.0 - 0.5


def resample(heights, layer, x0, z0, spacing, columns, rows):
    """Heights on an even grid in local metres. Sample [r, c] is at
    (x0 + c * spacing, z0 + r * spacing)."""
    xs = x0 + np.arange(columns) * spacing
    zs = z0 + np.arange(rows) * spacing
    grid_x, grid_z = np.meshgrid(xs, zs)
    lon, lat = to_lonlat(grid_x, grid_z)
    col, row = layer_pixels(layer, lon, lat)
    return ndimage.map_coordinates(heights, [row, col], order=1, mode="nearest")


def layer_extent(layer):
    """The part of a layer's area that an even local grid can fill: (x0, z0, x1, z1)."""
    corners_lon = [layer["west"], layer["east"]]
    corners_lat = [layer["south"], layer["north"]]
    xs, zs = [], []
    for lon in corners_lon:
        for lat in corners_lat:
            x, z = to_local(lon, lat)
            xs.append(float(x))
            zs.append(float(z))
    xs.sort()
    zs.sort()
    # The inner corners, so the grid stays inside the data everywhere.
    return xs[1], zs[1], xs[2], zs[2]
