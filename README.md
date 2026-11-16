# Ideal World

Ideal World is a single-player 3D physics sandbox built in Godot 4. Build machines from blocks on a grid, press Spawn, and drive, fly or float them through an open world. Real units, idealized physics, exact gears. A free personal project.

## Status

Early development. **Milestone 1: Build mode** is mostly in place, and **Milestone 2: Spawn** has its first basic version.

Working now:

- A 32 m × 64 m build pad with a 0.25 m grid (128 × 256 cells, 128 cells high)
- A blocky character with a walk animation who steps up ledges two blocks high, with a camera that scrolls from first person out to a wide third-person view
- A hollow garage behind the start point, with its door facing the build pad. The **Open garage** button at the top of the screen takes the door away and puts it back.
- Sitting: walk up to a seat and press E to sit in it, Space to stand up
- A mini map in the top-right corner showing the garage, the pad, nearby trees and where you are
- Grass and groves of trees, starting well back from the pad and garage
- All five tools: Place, Delete, Config, Transform and Paint
- A parts menu that stays out of the way: category tabs up the left edge, with the parts list opening beside them only while a tab is open
- A placement ghost that shows the part's own X, Y and Z axes in red, green and blue, so you can see which way it faces as you turn it
- **Basic Spawn:** the build is welded into rigid bodies that fall under gravity, collide, and can be pushed around by the character. Hinges turn.
- Twenty-two shapes in three groups. Basic: block, wedge, triangle wedge, cylinder, sphere. Structural: half block, plate, post, rod. Advanced: corner wedge, inverse corner, pyramid, cone, tapered cylinder, hemisphere, half cylinder, convex curve, concave curve, arch, ring, pipe, torus.
- Display models for eighteen mechanical parts: motor, servo, door hinge servo, hinge, ball joint, bearing block, piston, solenoid, spring, gear, bevel gear, rack, belt pulley, crankshaft, wheel, linkage bar, clutch and brake. They are models only and do nothing until Spawn is built.
- Display models for every other planned part: 13 fluid and engine parts, 4 aero parts, 11 logic blocks and sensors, 4 combat parts, and the seat, anchor block and dynamic offsetter. Also models only for now. That makes 75 parts in nine categories.
- Twenty-nine materials with real densities, from foam to gold, plus free choice of color, and one ideal material, **Frictionless surface**: nothing grips it, and once spawned it cannot be moved or damaged
- Resizing any part in steps of 0.005 block (1.25 mm), with live volume, mass and health
- Total mass and a center-of-mass marker for the whole build
- Saving and loading builds as shareable text files
- Undo and redo for every change, up to 100 steps back
- Signal linking in the Config tool: connect any part's input to another part's output, with lines showing the links. Links are stored and saved now and carry signals once Spawn and Logic are built.
- Settings for every functional part in the Config tool: motor torque and speed, piston lengths, speed and easing, gear teeth, light color, blast radius and so on. They are stored and saved now and take effect once Spawn is built.

Not built yet: the behavior of the mechanical, logic and combat parts, apart from the hinge. Once spawned, every other part is simply welded solid.

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
| Enter | Spawn the build, or go back to building |
| Scroll wheel | Zoom between first person and third person |
| Hold right mouse | Turn the camera (third person) |
| Esc | Free or recapture the cursor (first person) |
| 1 to 5 | Place, Delete, Config, Transform, Paint. Press the same key again to put the tool away. |
| Ctrl+Z / Ctrl+Y | Undo / redo (also the Undo and Redo buttons, bottom right) |
| Left click | Use the current tool |
| R / T / Y | Turn 90° about X / Y / Z: the part you are about to place, or the Transform selection. The red, green and blue buttons at the bottom left do the same. |

### Tools

The game starts with no tool in hand and nothing but the tabs and the tool bar on screen. Pick a tool with its number key or its button; pick the same one again to put it away and close its menu.

- **Place.** Pick a part from the menu and click to place it against whatever you point at. Category tabs run up the left edge of the screen. Picking the Place tool opens the narrow list of parts for the category you last used. Click another tab to switch category, or the open tab to fold the list away. The search box at the bottom left finds a part by name across every category. The ghost part under the cursor shows its X, Y and Z axes as red, green and blue lines. Aero panels are placed in the middle of the cell, with their thickness even either side of its center line. Picking a new part resets its rotation. New parts use the Paint tool's current material and color.
- **Delete.** Click a part to remove it.
- **Config.** Click a part to see its volume, mass and health, to change its dimensions, and to edit its settings if it has any. Red, green and blue lines on the selected part show its own X, Y and Z, in the same colors as the three size boxes. Shift+C (or Copy config) remembers the part's size and settings, and Shift+V (or Paste config) gives them to whichever part you select next, as many times as you like; the copy is kept until you copy another or press Spawn. To link a signal, press Link beside one of the part's inputs, then click the part the signal should come from; if that part has several outputs, pick one from the list that appears. Clear removes a link. Green lines show where the selected part's inputs come from and blue lines show where its outputs go. A part keeps its low corner in place when resized. While the Config or Transform tool is out, a labeled yellow ball marks the build's center of mass, and a labeled blue ball marks its center of lift if it has aero panels. Both show through the build. The center of lift is worked out for level flight at a 5° angle of attack, facing the way the first seat faces.
- **Transform.** Click to select a part; Shift+click adds to the selection. Arrow keys move the selection along the ground and Page Up / Page Down move it vertically, by the step chosen in the panel. Ctrl+C copies and Ctrl+X cuts. To paste, press the Paste button and click where the copy should go (a preview follows the cursor), or point and press Ctrl+V. However large the copy is, it rests on the surface you point at instead of sinking into it. **Paste in place** (Ctrl+Shift+V) puts the copy exactly where it was copied from and selects it, so you can step it along X, Y or Z with the arrow keys, Page Up / Page Down or the Move buttons. Ctrl+A selects everything, and Delete removes the selection.
- **Paint.** Choose a material and a color, then click parts to paint them. Hover a material to see its density, friction and strength. The two Pick buttons copy the material or the color from a part you click.

Parts of the same material may overlap. Parts of different materials may not.

## Spawn

Press the green **Spawn** button at the bottom left, or the Enter key, to set the build loose. Press the same button, now labeled **Build**, or Enter again, to put everything back on the pad exactly as it was.

The bottom-right corner shows which build of the game is running (for example "Build 12"). Beside the speed it shows the g-force the character feels: 1 g standing still, 0 g in free fall, more in a hard turn or pull-up, which helps to check that the newest copy is the one open.

This is the basic version. What it does so far:

- **Welding.** Parts whose bounding boxes share a face (or part of one) or overlap are welded into one rigid body. Parts that only meet along an edge or at a corner are not. Separate groups become separate bodies.
- **Mass.** Each body has the combined mass and center of mass of its parts, from their real volumes and densities. Its friction is the mass-weighted average of its materials.
- **Gravity and collisions.** Bodies fall, collide, stack and tip over.
- **Pushing.** The character has a mass of 70 kg. Walking into a body pushes it with a force equal to the character's momentum toward it (mass × closing speed) handed over across a quarter of a second, but never harder than the feet can grip: grip × weight, about 687 N on the ground and next to nothing on ice. Friction with the ground decides the rest. A light body slides away, a heavier one moves slowly and holds you back to its speed, and one whose friction is greater than the push does not move at all. Every push is a force in newtons from the game's own code; the physics engine itself never shoves a body out of the character's way.
- **Weight and grip.** A body you stand on carries your weight, and feels the reaction of your feet: speed up, slow down or push on something while standing on a loose body and it is pushed the other way. The character changes speed only as fast as its grip allows (grip × g), so it takes a moment to get going on the ground, is slippery on ice, and cannot change speed at all on a frictionless surface.
- **Seats** work the same as on the pad: E to sit, Space to stand up.
- **Hinges** work. A hinge splits across its middle into a base half and a top half, joined by the pin along its own X axis. Each side welds to whatever touches it, so what is attached to the top swings relative to what is attached to the base. Something that touches both sides, such as a block standing beside the hinge, welds to the side it shares more area with, and to the base if they are even. The hinge's settings apply: angle limits (off by default, so it turns freely) and friction torque. The two bodies a joint connects do not collide with each other, so use the angle limits to stop it where it should stop. If both sides of a joint end up welded to the same body through other parts, it cannot turn, and the spawn message says how many joints are locked that way.
- **Motors and servos** work the same way: the housing is the base and the output on top is the side that turns. Whatever touches the top face turns with it. A **motor** turns about its own +Y at up to its max speed, with up to its max torque; link Clockwise or Counterclockwise to input blocks, or link Speed to a number from −1 to 1. A **servo** also turns about its own +Y, and a **door hinge servo** swings its upright leaf about the edge it shares with its base plate. Link Go to positive target and Go to negative target to input blocks, and the servo moves to those angles at its set speed and returns to its default angle, or holds, when neither is on; or link Angle to a number of degrees. Angles are zero as built, and positive is counterclockwise seen from the top looking back at the base. Each drive works through its joint: the physics engine holds the turning speed the drive asks for as part of solving the joint, with at most the drive's max torque, so a servo holds its angle rigidly however light or heavy the thing it turns, and the base feels the opposite torque.
- **Thrusters** push along their own −Z with the thrust set in Config. With nothing linked a thruster runs flat out from the moment of spawning. Link its On input to an **input block** (Config tool, Signals) to run it from a key, or link Throttle to an input block set to "Number from two keys" to drive it forward and back. Key binds work only while you are sitting in a seat. A running thruster shows a glow.
- **Aero panels** make lift and drag. Each panel takes the air's speed at its own center, finds its angle of attack, and applies lift = ½ × air density × speed² × area × lift coefficient at right angles to the airflow, and drag along it. The lift coefficient is 4.0 per radian up to the 15° stall and follows a flat plate (sin 2α) beyond it; the drag coefficient is 0.01 + 2 sin²α. A panel is flat, so it makes no lift at zero angle of attack. The **dragless** panels make the same lift with no drag at all. Air density is 1.225 kg/m³ at the ground and thins with height.
- A body that contains an **anchor block**, or any part made of the **Frictionless surface** material, is fixed in place. A **dynamic offsetter** is invisible and has no collision once spawned, but still welds.

Not yet: apart from hinges, motors, servos, thrusters, aero panels and input blocks, every joint, wheel, engine and logic block is welded solid and does nothing. Gears and belts do not carry motion yet. There is no drag on anything but aero panels yet. Hollow shapes (arch, ring, pipe, torus, concave curve) collide as their filled-in outline while spawned.

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
| `scripts/player.gd` | Character movement, step-up, pushing and camera |
| `scripts/build_grid.gd` | Stores every part; overlap rules, mass and center of mass |
| `scripts/build_controller.gd` | The five build tools, sitting, and switching between building and spawned |
| `scripts/spawner.gd` | Spawn: welds the build into rigid bodies |
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
| `shaders/ground.gdshader` | The grass on the open ground |

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
