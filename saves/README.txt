IDEAL WORLD - SAVES FOLDER
==========================

Every .json file in this folder is one saved build. The game's Saves window
(the Saves button, bottom right) lists whatever is here.

  - To share a build, send someone its .json file.
  - To add a build someone sent you, drop its .json file in this folder and
    press Refresh in the Saves window.
  - To remove a build, delete its file here or use Delete in the game.

The files are plain text. You can open them in any text editor, and you can
write them by hand or with your own program.


FILE FORMAT
-----------

{
    "format": "ideal-world-build",
    "version": 1,
    "name": "My build",
    "block_size_m": 0.25,
    "parts": [
        {
            "type": "block",
            "pos": [20.5, 0.5, 10.5],
            "size": [1, 1, 1],
            "x_axis": [1, 0, 0],
            "y_axis": [0, 1, 0],
            "z_axis": [0, 0, 1],
            "material": "steel",
            "color": "#7a8088"
        }
    ]
}

"format" and "parts" are required. For each part, "type" and "pos" are
required and everything else is optional.

  type      Which part it is. See the list below.

  pos       Where the CENTER of the part is, in blocks, measured from the
            corner of the build pad. X runs 0 to 128, Y (up) 0 to 128,
            Z 0 to 256. A one-block part sitting on the pad in the very
            first cell has pos [0.5, 0.5, 0.5].

  size      The part's size in blocks along its own X, Y and Z.
            Left out: the part's normal size.
            The smallest step is 0.005 block.

  x_axis,   Where the part's own X, Y and Z directions point after it has
  y_axis,   been turned. Each is a list of three whole numbers made of one
  z_axis    1 or -1 and two 0s. Left out: not turned.
            Example, a quarter turn about Y:
            "x_axis": [0, 0, -1], "y_axis": [0, 1, 0], "z_axis": [1, 0, 0]

  material  The material's id. Left out: plastic. See the list below.

  color     A web color such as "#ff8800". Left out: the material's own color.

Parts that do not fit are skipped when the file loads: an unknown type, a
position outside the pad, or a part overlapping one of a different material.
Parts of the same material are allowed to overlap.


PART TYPES
----------

Basic:       block, wedge, triangle_wedge, cylinder, sphere
Structural:  slab, plate, post, rod
Advanced:    corner_wedge, inverse_corner, pyramid, cone, frustum,
             hemisphere, half_cylinder, convex_curve, concave_curve, arch,
             ring, pipe, torus
Mechanical:  motor, servo, door_hinge_servo, hinge, ball_joint, bearing,
             piston, solenoid, spring, gear, bevel_gear, rack, pulley,
             crankshaft, wheel, linkage_bar, clutch, brake
Logic:       light_panel, vanish_block, impact_detector
Combat:      explosive_block, machine_gun, large_cannon, ammo_generator


MATERIALS
---------

foam, balsa, cork, wood, oak, ice, plastic, rubber, nylon, acrylic, kevlar,
carbon_fiber, magnesium, fiberglass, brick, concrete, glass, aluminum,
granite, diamond, titanium, cast_iron, steel, brass, copper, silver, lead,
tungsten, gold
