"""A small kit for writing Ideal World build files from Python.

Everything is in grid cells (0.25 m). A part is placed by the world box it
fills and the way its own axes point; the kit works out the size along the
part's own axes, so a wedge or a servo can be turned any quarter-turn way.
"""
import json

X0 = 128.0          # the build's centreline


def cross(a, b):
    return [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]


def neg(a):
    return [-a[0], -a[1], -a[2]]


def det(x, y, z):
    c = cross(y, z)
    return x[0] * c[0] + x[1] * c[1] + x[2] * c[2]


IDENT = ([1, 0, 0], [0, 1, 0], [0, 0, 1])


def r5(v):
    return round(v * 200.0) / 200.0


class Build:
    def __init__(self, name):
        self.name = name
        self.parts = []

    # --- placing -------------------------------------------------------------
    def add(self, ptype, box, axes=IDENT, color="#18181b", material="balsa", settings=None, links=None):
        """box: (x0, x1, y0, y1, z0, z1) in cells. Returns the part's index."""
        x0, x1, y0, y1, z0, z1 = box
        assert x1 > x0 and y1 > y0 and z1 > z0, (ptype, box)
        world = [x1 - x0, y1 - y0, z1 - z0]
        xa, ya, za = [list(map(float, a)) for a in axes]
        assert abs(det(xa, ya, za) - 1.0) < 1e-6, (ptype, axes)
        size = []
        for axis in (xa, ya, za):
            k = max(range(3), key=lambda i: abs(axis[i]))
            size.append(r5(world[k]))
        part = {
            "type": ptype, "material": material, "color": color,
            "pos": [r5((x0 + x1) / 2), r5((y0 + y1) / 2), r5((z0 + z1) / 2)],
            "size": size, "x_axis": xa, "y_axis": ya, "z_axis": za,
        }
        if settings:
            part["settings"] = settings
        if links:
            part["links"] = links
        self.parts.append(part)
        return len(self.parts) - 1

    def box(self, box, color, ptype="block", **kw):
        return self.add(ptype, box, IDENT, color, **kw)

    def wedge(self, box, full_a, full_b, color, ptype="wedge", **kw):
        """A wedge whose two full faces look along full_a and full_b (outward
        world directions); the slope faces the other way."""
        x = neg(full_a)
        y = neg(full_b)
        z = cross(x, y)
        return self.add(ptype, box, (x, y, z), color, **kw)

    def corner(self, box, a, b, c, color, **kw):
        """A corner wedge with its three full faces looking along a, b, c."""
        x, y, z = neg(a), neg(b), neg(c)
        if det(x, y, z) < 0:
            y, z = z, y
        return self.add("corner_wedge", box, (x, y, z), color, **kw)

    def tri_panel(self, box, u, v, color, ptype="aero_panel_triangle", **kw):
        """A triangle panel filling box, its right angle at the corner the legs
        leave from: u is the world direction of one leg, v of the other."""
        x = list(u)
        z = neg(v)
        y = cross(z, x)
        return self.add(ptype, box, (x, y, z), color, **kw)

    def flat_tri(self, box, u, v, color, **kw):
        """A flat right-triangle plate (a thin wedge): its right angle at the
        corner the legs leave from, along world directions u and v."""
        x = list(u)
        y = list(v)
        z = cross(x, y)
        return self.add("wedge", box, (x, y, z), color, **kw)

    def along(self, ptype, box, direction, color, **kw):
        """A round part (cylinder, cone, frustum) whose own Y runs along a world
        axis direction: (0,0,1) points it at the nose."""
        y = list(direction)
        x = [1, 0, 0] if abs(y[0]) < 0.5 else [0, 1, 0]
        z = cross(x, y)
        return self.add(ptype, box, (x, y, z), color, **kw)

    def link(self, index, port, source, output):
        self.parts[index].setdefault("links", {})[port] = {"part": source, "output": output}

    def write(self, path):
        data = {"block_size_m": 0.25, "format": "ideal-world-build", "name": self.name,
                "parts": self.parts, "version": 1}
        with open(path, "w") as f:
            json.dump(data, f, indent=1)


def side_box(s, dx0, dx1, y0, y1, z0, z1):
    """A box given by distances out from the centreline, on side s (+1 left
    of the pilot, -1 right)."""
    a, b = X0 + s * dx0, X0 + s * dx1
    return (min(a, b), max(a, b), y0, y1, z0, z1)


def holes_cut(rect, holes):
    """Splits rectangle (a0, a1, b0, b1) into pieces that leave out the holes."""
    pieces = [rect]
    for h in holes:
        out = []
        for (a0, a1, b0, b1) in pieces:
            if h[1] <= a0 or h[0] >= a1 or h[3] <= b0 or h[2] >= b1:
                out.append((a0, a1, b0, b1))
                continue
            if h[0] > a0:
                out.append((a0, h[0], b0, b1))
            if h[1] < a1:
                out.append((h[1], a1, b0, b1))
            m0, m1 = max(a0, h[0]), min(a1, h[1])
            if h[2] > b0:
                out.append((m0, m1, b0, h[2]))
            if h[3] < b1:
                out.append((m0, m1, h[3], b1))
        pieces = out
    return pieces
