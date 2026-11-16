"""Downloads the real terrain around Flathead Lake for Ideal World's map.

Run it once on your own computer (the game itself never downloads anything):

    pip install pillow numpy
    python tools/fetch_terrain.py

It fetches elevation tiles from the free "Terrain Tiles" set on AWS Open Data
(Terrarium format, built mostly from USGS 3DEP elevation data), stitches them,
and writes three files into map/:

    map/terrain_lake.png     the whole lake and the mountains around it, ~12.8 m per pixel
    map/terrain_islands.png  Wild Horse, Cromwell, Melita and Dream Islands, ~3.2 m per pixel
    map/terrain.json         where each image sits on the Earth, and how heights are stored

Both images are 16-bit greyscale. Each pixel is the height above sea level in
decimetres, less 700 m:  height_m = 700 + pixel / 10.  The lake surface (882 m)
is about pixel 1820. The elevation data shows the lake as flat water; its bottom
is shaped later, in the game's map builder.

Downloaded tiles are kept in tools/terrain_cache/, so running it again only
fetches what is missing. Commit and push the map/ folder when it is done.

Elevation data: Mapzen Terrain Tiles on AWS Open Data. Sources include USGS 3DEP
(public domain) and SRTM. See https://registry.opendata.aws/terrain-tiles/
"""

import io
import json
import math
import os
import sys
import time
import urllib.request

try:
    import numpy as np
    from PIL import Image
except ImportError:
    sys.exit("Please install the two helpers first:  pip install pillow numpy")

TILE_URL = "https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png"
BASE_HEIGHT = 700.0   # metres; stored heights are (height - BASE_HEIGHT) x 10
SCALE = 10.0

# name: (west, east, south, north) in degrees, and zoom level
AREAS = {
    "lake": ((-114.55, -113.75, 47.60, 48.15), 13),
    "islands": ((-114.32, -114.16, 47.80, 47.88), 15),
}

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
CACHE = os.path.join(HERE, "terrain_cache")
OUT = os.path.join(ROOT, "map")


def tile_xy(lon, lat, zoom):
    """The tile a point falls in, as fractional tile numbers."""
    n = 2 ** zoom
    x = (lon + 180.0) / 360.0 * n
    lat_r = math.radians(lat)
    y = (1.0 - math.log(math.tan(lat_r) + 1.0 / math.cos(lat_r)) / math.pi) / 2.0 * n
    return x, y


def tile_lon(x, zoom):
    return x / 2 ** zoom * 360.0 - 180.0


def tile_lat(y, zoom):
    n = math.pi - 2.0 * math.pi * y / 2 ** zoom
    return math.degrees(math.atan(math.sinh(n)))


def fetch(zoom, x, y):
    """One tile's heights in metres, as a 256 x 256 array."""
    path = os.path.join(CACHE, str(zoom), str(x), "%d.png" % y)
    if not os.path.exists(path):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        url = TILE_URL.format(z=zoom, x=x, y=y)
        request = urllib.request.Request(url, headers={"User-Agent": "IdealWorld-terrain-fetch/1.0"})
        for attempt in range(4):
            try:
                with urllib.request.urlopen(request, timeout=30) as reply:
                    data = reply.read()
                break
            except Exception as problem:   # network hiccup: wait and try again
                if attempt == 3:
                    raise
                print("  retrying %s (%s)" % (url, problem))
                time.sleep(2.0 * (attempt + 1))
        with open(path, "wb") as handle:
            handle.write(data)
        time.sleep(0.05)   # be gentle with the server
    rgb = np.asarray(Image.open(path).convert("RGB"), dtype=np.float64)
    return rgb[:, :, 0] * 256.0 + rgb[:, :, 1] + rgb[:, :, 2] / 256.0 - 32768.0


def build(name, box, zoom):
    west, east, south, north = box
    x0, y0 = tile_xy(west, north, zoom)
    x1, y1 = tile_xy(east, south, zoom)
    x0, y0, x1, y1 = int(x0), int(y0), int(x1), int(y1)
    across, down = x1 - x0 + 1, y1 - y0 + 1
    print("%s: %d x %d tiles at zoom %d" % (name, across, down, zoom))
    heights = np.zeros((down * 256, across * 256), dtype=np.float64)
    done = 0
    for ty in range(down):
        for tx in range(across):
            heights[ty * 256:(ty + 1) * 256, tx * 256:(tx + 1) * 256] = fetch(zoom, x0 + tx, y0 + ty)
            done += 1
            if done % 25 == 0 or done == across * down:
                print("  %d of %d tiles" % (done, across * down))
    stored = np.clip(np.round((heights - BASE_HEIGHT) * SCALE), 0, 65535).astype(np.uint16)
    file_name = "terrain_%s.png" % name
    Image.fromarray(stored).save(os.path.join(OUT, file_name))
    print("  heights %.1f m to %.1f m, saved map/%s" % (heights.min(), heights.max(), file_name))
    return {
        "file": file_name,
        "zoom": zoom,
        "tile_x": x0, "tile_y": y0, "tiles_across": across, "tiles_down": down,
        "pixels": [across * 256, down * 256],
        # The outer edges of the image. Pixels are evenly spaced in Web Mercator,
        # so latitude is not linear down the image: use the tile numbers to convert.
        "west": tile_lon(x0, zoom), "east": tile_lon(x1 + 1, zoom),
        "north": tile_lat(y0, zoom), "south": tile_lat(y1 + 1, zoom),
        "lowest_m": float(heights.min()), "highest_m": float(heights.max()),
    }


def main():
    os.makedirs(OUT, exist_ok=True)
    os.makedirs(CACHE, exist_ok=True)
    layers = {}
    for name, (box, zoom) in AREAS.items():
        layers[name] = build(name, box, zoom)
    info = {
        "projection": "Web Mercator tiles (EPSG:3857), 256 pixels each",
        "height_m": "%g + pixel / %g" % (BASE_HEIGHT, SCALE),
        "base_height_m": BASE_HEIGHT, "pixels_per_metre_of_height": SCALE,
        "lake_surface_m": 882.0,
        "source": "Mapzen Terrain Tiles (Terrarium) on AWS Open Data; USGS 3DEP, SRTM and others",
        "layers": layers,
    }
    with open(os.path.join(OUT, "terrain.json"), "w") as handle:
        json.dump(info, handle, indent=2)
    # Keep Godot from importing these large images as textures.
    open(os.path.join(OUT, ".gdignore"), "w").close()
    print("Done. Commit and push the map folder.")


if __name__ == "__main__":
    main()
