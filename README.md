# Ideal World

Ideal World is a single-player 3D physics sandbox built in Godot 4. Build machines from blocks on a grid, press Spawn, and drive, fly or float them through an open world. Real units, idealized physics, exact gears. A free personal project.

## Status

Early development, partway through **Milestone 1: Build mode**.

Working now:

- A 128 m × 256 m build pad with a 1 m grid (128 × 256 cells, 128 cells high)
- A blocky character who steps up one-block ledges, with a camera that scrolls from first person out to a wide third-person view
- All five tools: Place, Delete, Transform, Config and Paint
- Twelve shapes: block, wedge, triangle wedge, cylinder, sphere, corner wedge, pyramid, cone, hemisphere, convex curve, concave curve and ring
- Thirteen materials with real densities, plus free choice of color
- Resizing any part in 5 mm steps, with live volume, mass and health
- Total mass and a center-of-mass marker for the whole build

Not built yet: saving and loading, mechanical and logic parts, and everything to do with Spawn and physics.

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
| Space | Jump |
| Scroll wheel | Zoom between first person and third person |
| Hold right mouse | Turn the camera (third person) |
| Esc | Free or recapture the cursor (first person) |
| 1 to 5 | Place, Delete, Transform, Config, Paint |
| Left click | Use the current tool |
| R / T / Y | Turn 90° about X / Y / Z: the part you are about to place, or the Transform selection |

### Tools

- **Place.** Pick a part from the menu and click to place it against whatever you point at. Picking a new part resets its rotation. New parts use the Paint tool's current material and color.
- **Delete.** Click a part to remove it.
- **Transform.** Click to select a part; Shift+click adds to the selection. Arrow keys move the selection along the ground and Page Up / Page Down move it vertically, by the step chosen in the panel. Ctrl+C copies, Ctrl+X cuts, Ctrl+V pastes where you point, Ctrl+A selects everything, and Delete removes the selection.
- **Config.** Click a part to see its volume, mass and health and to change its dimensions. A part keeps its low corner in place when resized. The yellow ball marks the build's center of mass.
- **Paint.** Choose a material and a color, then click parts to paint them. Hover a material to see its density, friction and strength. The two Pick buttons copy the material or the color from a part you click.

Parts of the same material may overlap. Parts of different materials may not.

## Units

One grid cell is a 1 meter cube. Sizes and positions are stored as whole multiples of 5 mm. The simulation works in SI units at true size: meters, kilograms, newtons. Y is up; X and Z are the ground plane.

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
| `scripts/material_library.gd` | Materials: density, friction, strength, look |
| `scripts/hud.gd` | The on-screen interface |
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
