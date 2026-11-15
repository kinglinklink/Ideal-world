# Ideal World

Ideal World is a single-player 3D physics sandbox built in Godot 4. Build machines from blocks on a decimeter grid, press Spawn, and drive, fly or float them through an open world. Real units, idealized physics, exact gears. A free personal project.

## Status

Early development. This is the first playable slice of **Milestone 1: Build mode**.

Working now:

- A 12.8 m × 25.6 m build pad with a 1 dm grid (128 × 256 cells, 128 cells high)
- A blocky character with a camera that scrolls from first person out to a wide third-person view
- The Place and Delete tools, with a preview of what you are about to place or delete
- Two parts, a block and a wedge, with 90° rotation before placing

Not built yet: the Transform, Config and Paint tools, materials, saving, and everything to do with Spawn and physics.

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
| 1 | Place tool |
| 2 | Delete tool |
| Left click | Use the current tool |
| R / T / Y | Rotate the part 90° about X / Y / Z before placing |

Picking a new part from the menu resets its rotation.

## Units

One grid cell is a 1 decimeter cube. The simulation works in SI units at true size: meters, kilograms, newtons. Y is up; X and Z are the ground plane.

## Project layout

| Path | Contents |
| --- | --- |
| `project.godot` | Project settings: Jolt physics, 240 physics steps per second |
| `scenes/main.tscn` | The one scene. Everything else is built in code. |
| `scripts/main.gd` | Sets up the sky, ground, build pad, player, tools and interface |
| `scripts/player.gd` | Character movement and camera |
| `scripts/build_grid.gd` | Stores which grid cells hold which parts |
| `scripts/build_controller.gd` | The build tools |
| `scripts/part_library.gd` | Part definitions: meshes and collision shapes |
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
