"""Downloads the real roads and buildings around Flathead Lake for Ideal World.

Run it once on your own computer, like fetch_terrain.py (no extra installs):

    python tools/fetch_osm.py

It asks OpenStreetMap's free Overpass service for every road and building
outline over the same area as the terrain (the lake, the towns on its shore,
and the land out to the mountains), in 16 pieces so each request stays small,
and writes them to map/osm.json. That takes a few minutes. Pieces already
downloaded are kept in tools/osm_cache/, so running it again only fetches
what is missing. Commit and push map/osm.json when it is done.

Map data (c) OpenStreetMap contributors, available under the Open Database
License: https://www.openstreetmap.org/copyright
"""

import json
import os
import sys
import time
import urllib.parse
import urllib.request

# The terrain's area: west, east, south, north.
AREA = (-114.55, -113.75, 47.60, 48.15)
PIECES = 4   # split into PIECES x PIECES requests
ENDPOINTS = [
    "https://overpass-api.de/api/interpreter",
    "https://lz4.overpass-api.de/api/interpreter",
]
ROAD_KINDS = ("motorway|trunk|primary|secondary|tertiary|unclassified|residential|living_street|"
              "service|track|motorway_link|trunk_link|primary_link|secondary_link|tertiary_link")
QUERY = """[out:json][timeout:180];
(
  way["highway"~"^({kinds})$"]({south},{west},{north},{east});
  way["building"]({south},{west},{north},{east});
);
out tags geom;
"""

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
CACHE = os.path.join(HERE, "osm_cache")
OUT = os.path.join(ROOT, "map", "osm.json")


def ask(query):
    """Sends one query, trying again (and the other server) if it is busy."""
    body = urllib.parse.urlencode({"data": query}).encode("utf-8")
    for attempt in range(8):
        url = ENDPOINTS[attempt % len(ENDPOINTS)]
        request = urllib.request.Request(url, data=body, headers={"User-Agent": "IdealWorld-map-fetch/1.0"})
        try:
            with urllib.request.urlopen(request, timeout=300) as reply:
                return json.loads(reply.read().decode("utf-8"))
        except Exception as problem:   # busy, timed out, or a network hiccup
            wait = 15 * (attempt + 1)
            print("  the map server said: %s; trying again in %d s" % (problem, wait))
            time.sleep(wait)
    raise RuntimeError("The map server did not answer. Please run the script again later.")


def piece(i, k):
    west, east, south, north = AREA
    w = west + (east - west) * i / PIECES
    e = west + (east - west) * (i + 1) / PIECES
    s = south + (north - south) * k / PIECES
    n = south + (north - south) * (k + 1) / PIECES
    path = os.path.join(CACHE, "piece_%d_%d.json" % (i, k))
    if os.path.exists(path):
        with open(path) as handle:
            return json.load(handle)
    query = QUERY.format(kinds=ROAD_KINDS, south=s, west=w, north=n, east=e)
    data = ask(query)
    with open(path, "w") as handle:
        json.dump(data, handle)
    time.sleep(2)   # be gentle with the free service
    return data


def number(text):
    """The number at the start of a tag like "12", "12 m" or "3.5", or None."""
    try:
        return float(str(text).split()[0].replace(",", "."))
    except (ValueError, IndexError):
        return None


def main():
    os.makedirs(CACHE, exist_ok=True)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    roads = {}
    buildings = {}
    done = 0
    for i in range(PIECES):
        for k in range(PIECES):
            data = piece(i, k)
            done += 1
            print("piece %d of %d" % (done, PIECES * PIECES))
            for element in data.get("elements", []):
                if element.get("type") != "way" or "geometry" not in element:
                    continue
                tags = element.get("tags", {})
                points = [[round(p["lon"], 6), round(p["lat"], 6)] for p in element["geometry"]]
                if len(points) < 2:
                    continue
                if "building" in tags:
                    if len(points) < 4:
                        continue
                    buildings[element["id"]] = {
                        "kind": tags.get("building", "yes"),
                        "levels": number(tags.get("building:levels")),
                        "height": number(tags.get("height")),
                        "name": tags.get("name"),
                        "outline": points,
                    }
                elif "highway" in tags:
                    roads[element["id"]] = {
                        "kind": tags["highway"],
                        "name": tags.get("name") or tags.get("ref"),
                        "surface": tags.get("surface"),
                        "lanes": number(tags.get("lanes")),
                        "line": points,
                    }
    result = {
        "source": "OpenStreetMap contributors, ODbL (https://www.openstreetmap.org/copyright)",
        "area": AREA,
        "roads": list(roads.values()),
        "buildings": list(buildings.values()),
    }
    with open(OUT, "w") as handle:
        json.dump(result, handle, separators=(",", ":"))
    print("Done: %d roads and %d buildings in map/osm.json (%.1f MB). Commit and push it."
          % (len(roads), len(buildings), os.path.getsize(OUT) / 1e6))


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit("Stopped. Run it again to carry on where it left off.")
