# Ideal World

Ideal World is a single-player 3D physics sandbox built in Godot 4. Build machines from blocks on a grid, press Spawn, and drive, fly or float them through an open world. Real units, idealized physics, exact gears. A free personal project.

## Status

Early development, partway through **Milestone 1: Build mode**.

Working now:

- A 32 m × 64 m build pad with a 0.25 m grid (128 × 256 cells, 128 cells high)
- A blocky character with a walk animation who steps up ledges two blocks high, with a camera that scrolls from first person out to a wide third-person view
- A hollow garage behind the start point, with its door facing the build pad. The **Open garage** button at the top of the screen takes the door away and puts it back.
- Sitting: walk up to a seat and press E to sit in it, Space to stand up
- A mini map in the top-right corner showing the garage, the pad, nearby trees and where you are
- Grass and groves of trees, starting well back from the pad and garage
- All five tools: Place, Delete, Transform, Config and Paint
- Twenty-two shapes in three groups. Basic: block, wedge, triangle wedge, cylinder, sphere. Structural: half block, plate, post, rod. Advanced: corner wedge, inverse corner, pyramid, cone, tapered cylinder, hemisphere, half cylinder, convex curve, concave curve, arch, ring, pipe, torus.
- Display models for eighteen mechanical parts: motor, servo, door hinge servo, hinge, ball joint, bearing block, piston, solenoid, spring, gear, bevel gear, rack, belt pulley, crankshaft, wheel, linkage bar, clutch and brake. They are models only and do nothing until Spawn is built.
- Display models for every other planned part: 13 fluid and engine parts, 4 aero parts, 11 logic blocks and sensors, 4 combat parts, and the seat, anchor block and dynamic offsetter. Also models only for now. That makes 75 parts in nine categories.
- Twenty-nine materials with real densities, from foam to gold, plus free choice of color
- Resizing any part in steps of 0.005 block (1.25 mm), with live volume, mass and health
- Total mass and a center-of-mass marker for the whole build
- Saving and loading builds as shareable text files
- Undo and redo for every change, up to 100 steps back
- Signal linking in the Config tool: connect any part's input to another part's output, with lines showing the links. Links are stored and saved now and carry signals once Spawn and Logic are built.
- Settings for every functional part in the Config tool: motor torque and speed, piston lengths, speed and easing, gear teeth, light color, blast radius and so on. They are stored and saved now and take effect once Spawn is built.

Not built yet: Spawn, physics, and the behavior of the mechanical, logic and combat parts.

## How to run it

1. Download the latest stable **Godot 4** (standard version, 4.6 or newer) from [godotengine.org](https://godotengine.org/download).
2. Download this repository: click the green **Code** button, then **Download ZIP**, and unzip it. If you use Git, clone it instead.
3. Open Godot. In the project manager click **Import**, select the `project.godot` file in the unzipped folder, and open the project.
4. Press **F5** to play.

## Controls

| Input | Action |
| --- | --- |
| W A S D | Walk |
| Shift | Run |
| Space | Jump, or stand up from a seat |
| E | Sit in the nearest seat within reach |
| Scroll wheel | Zoom between first person and third person |
| Hold right mouse | Turn the camera (third person) |
| Esc | Free or recapture the cursor (first person) |
| 1 to 5 | Place, Delete, Transform, Config, Paint |
| Ctrl+Z / Ctrl+Y | Undo / redo (also the Undo and Redo buttons, bottom right) |
| Left click | Use the current tool |
| R / T / Y | Turn 90° about X / Y / Z: the part you are about to place, or the Transform selection |

### Tools

- **Place.** Pick a part from the menu and click to place it against whatever you point at. Category tabs run down the left of the menu, and the search box finds a part by name across all of them. Picking a new part resets its rotation. New parts use the Paint tool's current material and color.
- **Delete.** Click a part to remove it.
- **Transform.** Click to select a part; Shift+click adds to the selection. Arrow keys move the selection along the ground and Page Up / Page Down move it vertically, by the step chosen in the panel. Ctrl+C copies and Ctrl+X cuts. To paste, press the Paste button and click where the copy should go (a preview follows the cursor), or point and press Ctrl+V. Ctrl+A selects everything, and Delete removes the selection.
- **Config.** Click a part to see its volume, mass and health, to change its dimensions, and to edit its settings if it has any. To link a signal, press Link beside one of the part's inputs, then click the part the signal should come from; if that part has several outputs, pick one from the list that appears. Clear removes a link. Green lines show where the selected part's inputs come from and blue lines show where its outputs go. A part keeps its low corner in place when resized. The yellow ball marks the build's center of mass.
- **Paint.** Choose a material and a color, then click parts to paint them. Hover a material to see its density, friction and strength. The two Pick buttons copy the material or the color from a part you click.

Parts of the same material may overlap. Parts of different materials may not.

## Saves

Press the **Saves** button in the bottom-right corner. Type a name and press Save, or pick a build from the list and press Load. Loading replaces the current build and deleting is permanent, so both ask for a second click.

Every build is one `.json` file in the `saves` folder, next to `project.godot`. In an exported game the folder sits beside the program.

- **Share a build:** send someone its `.json` file.
- **Add a build:** drop its `.json` file into `saves` and press Refresh.
- **Make one outside the game:** the files are plain text. [`saves/README.txt`](saves/README.txt) describes the format, and `saves/example-gate.json` is a small build written by hand.

## Units

One grid cell is a 0.25 meter cube. Sizes and positions are stored as whole multiples of 0.005 block (1.25 mm). The scale is one number, `CELL`, in `scripts/units.gd`. The simulation works in SI units at true size: meters, kilograms, newtons. Y is up; X and Z are the ground plane.

## Project layout

| Path | Contents |
| --- | --- |
| `project.godot` | Project settings: Jolt physics, 240 physics steps per second |
| `scenes/main.tscn` | The one scene. Everything else is built in code. |
| `scripts/main.gd` | Sets up the sky, ground, build pad, player, tools and interface |
| `scripts/units.gd` | The grid scale and the smallest size increment |
| `scripts/player.gd` | Character movement, step-up and camera |
| `scripts/build_grid.gd` | Stores every part; overlap rules, mass and center of mass |
| `scripts/build_controller.gd` | The five build tools |
| `scripts/part_library.gd` | Part shapes: meshes, collision, volume |
| `scripts/mech_models.gd` | Display models for the mechanical parts |
| `scripts/mesh_kit.gd` | Helpers that build meshes from boxes, cylinders and gear discs |
| `scripts/material_library.gd` | Materials: density, friction, strength, look |
| `scripts/part_settings.gd` | The settings each kind of part has, with defaults and limits |
| `scripts/part_ports.gd` | The signal inputs and outputs each kind of part has |
| `scripts/save_manager.gd` | Saving and loading builds |
| `scripts/hud.gd` | The on-screen interface |
| `scripts/minimap.gd` | The mini map |
| `scripts/scenery.gd` | Grass and trees |
| `saves/` | Saved builds, the format guide and an example |
| `shaders/pad_grid.gdshader` | Draws the grid lines on the build pad |

## Roadmap

1. Build mode: grid, five tools, materials, character, camera, saves
2. Spawn: welding, collisions, friction, wheels, hinges, motors, seats
3. Drivetrain and actuators: gears, belts, cranks, pistons, servos, springs
4. Aerodynamics, drag, thrusters, lift gas
5. Logic, sensors, PID control
6. Fluids and engines
7. Water and buoyancy
8. The open world
9. Combat and health

## License

MIT. See [LICENSE](LICENSE).
