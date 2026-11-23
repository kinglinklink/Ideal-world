# Ideal World

Ideal World is a single-player 3D physics sandbox built in Godot 4. Build machines from blocks on a grid, press Spawn, and drive, fly or float them through an open world. Real units, idealized physics, exact gears. A free personal project.

## Status

Early development. **Milestone 1: Build mode** is mostly in place, and **Milestone 2: Spawn** has its first basic version.

### New in Build 33

- **B-2 Spirit** in the saves folder: a full-size flying wing, 52 m across, in dark grey, with a hatch and ladder underneath, landing gear that goes up by itself above 50 m (and comes down below 35 m), and a centre body full of bomb bays:
  - **43 small bombs** (about 750 kg each, 100 m blast) in a grid of bays, each a reload gate that hangs a fresh bomb 2 s after it drops one
  - **One huge bomb** (6.5 t, 500 m blast) in the middle, reloading in 3 s
  - **Four missiles** under the wings that fly straight ahead, reloading every half second
  - Every controller button drops part of the array (see below). Bombs drop only high enough that their blast can't reach the plane: small ones from 160 m above the ground, the big one from 800 m
- **To runway**: a new button beside Spawn (and in the pause menu) takes the whole build to the start of the nearest runway, level and facing down it; press again for the next runway. See [To runway](#to-runway)
- **Reload gate**: a Reload time input to change how fast it reloads as you go, a push-off speed that throws the payload clear of the rail, and a dropped payload is no longer hurt by its own build's blasts (so a stream of bombs can't set itself off back up to the bomber)
- **The stress model counted thrust and lift four times over** (they were added up over the four ticks between checks): fixed. Builds are now as strong against their own engines and wings as they should be
- **Faster logic and bombs**: gates are worked out once at spawn and in the order signals flow, so logic takes about a third of the time it did; dropped bombs skip the stress model and have lighter drag, impact detectors and explosives, so hundreds can fall at once
- Distance sensors with a long range no longer cost more to run

#### B-2 controls

| Controller | Keyboard | |
| --- | --- | --- |
| Left stick | W S A D | Pitch and roll (and nose-wheel steering, slowly, on the ground) |
| | Z X | Yaw (the drag rudders) |
| RT | K (full), M (cruise) | Throttle, 250 kN an engine |
| | Q | Air brake |
| A | 1 | Every small bay: the carpet |
| Y | 2 | The 500 m bomb |
| X | 3 | Middle row |
| B | 4 | The three middle columns |
| LB / RB | 5 / 6 | Left / right half |
| D-pad up / down | 7 / 8 | Front / back row |
| D-pad left / right | 9 / 0 | The two outermost columns on the left / right |
| LT | R | Missiles |

Hold a bomb button and those bays keep dropping as fast as they reload. Fly at least 160 m above the ground for the small bombs and 800 m for the big one. To take off, press To runway, run the throttle up, and pull back at about 80 m/s.

### New in Build 32

- **Reload gate** part (Combat): whatever is built on its rail (its top face) rides along welded to it until Release lets it go, then an identical copy is rebuilt on the rail after the reload time (3 s by default), wired to the same controls. Set how many reloads it has (0 for no limit) and how long explosives on it stay safe after letting go, so a missile can't blow up the plane that fired it. Outputs Loaded and Reloads used
- **Ladder** part (Structural): walk into it, or hold jump against it, to climb at 2 m/s; walk away to let go, and push on at the top to step off. Its Stowed input folds it away (hidden and not solid)
- **Pulse** mode for key input blocks: on for one physics tick each press, for stepping through things
- **F-14 Tomcat, faster and easier to board:**
  - The wings now sweep back the right way.
  - A boarding ladder on the left by the cockpit. It folds away once the engines run or the gear is up.
  - **Right trigger** (or K for full power, M for cruise): 500 kN a side.
  - **Left trigger** (or Shift): afterburners, only once the right trigger is fully in. Up to 5 MN a side. They spool over about 4 s and ease off at speed so the airframe isn't crushed, and it reaches the game's top speed of about 740 m/s (best high up).
  - **D-pad up** (or G): gear up once airborne, and again to lower it.
  - The four missiles sit on reload gates and the trigger fires the next loaded one. They are now heavier aluminium so they outrun the jet.

### New in Build 31

- **Xbox and PlayStation controllers** (USB or Bluetooth): left stick walks, right stick looks, A jumps, Y sits, View stands up (or spawns), Menu pauses. See [Controller](#controller)
- **Controller input** part (Logic): binds any button, stick, trigger or D-pad direction to a build. Sticks and triggers give smooth numbers with a dead zone, a response curve and a scale, and two controls can make one number (D-pad left and right, say); buttons can hold, toggle or pulse
- **F-14 Tomcat** in the saves folder: black balsa with red trim, swing wings, split door-hinge flaperons, elevators and rudders under one PID stability system, twin vectoring nozzles with hidden thrusters and engine glow, retracting gear with sliding doors, depleted-uranium cannons, nose guns and four missiles
- **Depleted uranium**: a new material, 19,050 kg/m³, for dense cannon shells
- **Stronger load paths in the stress model**: each part now hangs on the widest weld it has to the rest of the body, from the heaviest part near the centre of mass, so a wall welded along its whole edge no longer hangs from a corner it happens to touch
- **Seated, a build's keys are its own**: if one of its input blocks uses M, M no longer opens the map as well (Space and Esc keep their jobs)
- Fixed a spawned build sometimes flying apart when it landed on its pistons, and an error when a damaged part's smoke was cleared

### New in Build 30

- **The real trees of Flathead Lake**, fifteen kinds placed by where they grow: black cottonwood, quaking aspen, paper birch, Douglas hawthorn and serviceberry on the shore; ponderosa pine, Douglas-fir and Rocky Mountain juniper on low, dry, south-facing slopes; Douglas-fir, western redcedar, western larch and Rocky Mountain maple where it's low and shaded; lodgepole pine and larch higher up; Engelmann spruce and subalpine fir, then mountain hemlock near the tree line. Larches and the broadleaf trees turn their own autumn colours and stand bare in winter
- **Light and air**: ambient light from the sky (blue from above, darker from below), soft contact shadows (with the Shadows setting), a little glow round bright lights, haze that glows toward the sun, and morning mist over the lake, thickest at sunrise in spring and autumn and after rain

### New in Build 29

- **Merged drawing**: each spawned body's plain parts are drawn as one mesh per material (a 38-part build went from 38 draw calls to 1); parts that need their own look (scorch marks, the stress view) come back on their own
- **Town buildings** have windows on every storey, a door, gabled roofs on houses and parapets on flat roofs
- **Cottonwoods** along the lakeshore: broad leafy crowns that turn gold in autumn and go bare in winter
- **Water**: clearer, greener shallows and foam lapping at the shore
- **Instrument** part (Logic): a dashboard dial showing airspeed, altitude, an artificial horizon, fuel, or any linked value

### New in Build 28

- **Collision follows each part's real shape**: triangle panels are solid only where the triangle is; rings, pipes, arches and curves keep their holes when spawned; parts weld only where their shapes really meet
- **Glass, acrylic and diamond cast no shadow**
- **Faster birds**: far flocks update less often and birds past 1.5 km aren't drawn (about 1.6 ms down to 0.7 ms a frame)
- **Traffic looks like traffic**: cars with a bonnet, cabin, glass, wheels and bumpers; light planes with a round fuselage, tapered wings, tail, propeller and wheels

### New in Build 27

- **Three save slots** after Play, each keeping its money, races won, missions, bird guide and clock; switch slots from the pause menu
- **Missions board** (J): races not yet won, cargo runs and photo jobs, with markers on the full map (M) you can click for details and a waypoint
- **Birds of Flathead Lake**: 23 real species, as common or rare in the game as they are in life, with nests where each kind really nests (eggs in spring, chicks in summer). The **camera** (C) takes photos into a photos folder; photographing a bird ticks it off in the **bird guide** (B), which keeps in-game facts and real-world facts apart
- **Fuel stations** at the airports, by the town roads and at the docks: park in the green circle, get out and press F at the pump to fill up or spend a set amount
- **Damage effects**: smoke and scorch on hurt parts, burning fuel tanks that can explode, coughing engines, sparks on metal
- **Ghost racing**: race a see-through copy of your best run, in the build you used, on races you have won
- **Seasons you can see**: the lake freezes in winter (thick enough to drive on near the shore), wildflowers in spring, sailing, speed and fishing boats in summer, and **boat races** from Skeeko Bay, Melita, Cromwell and Shelter Islands and Polson
- **Bigger disasters**: an eruption column 15 km tall seen from anywhere, molten rocks lobbed kilometres, tornadoes 3 km tall, a tsunami wall 2,500 m high, a hurricane eye wall over the lake; an event distance setting for how far away they happen. A crater that burns anything that goes in
- **Build tools**: Scale (6) with handles to pull, Sub-assemblies (7) with a menu of little turning models to drag into a build, G to grab the selection; input, logic and PID parts go weightless and invisible once spawned
- **Inspector** (8, while spawned): logic links lit by their signals, shafts and gears ringed by load with rpm and torque, jammed gear trains in red, fluid pressure and flow, and a live card for the part under the pointer
- **Performance overlay** (F3): milliseconds per frame by subsystem, the heaviest picked out with what in your build is behind it
- **Test stand** beside the pad: a dyno (torque and power against rpm) and a wind tunnel up to 750 m/s (lift, drag, side force and pitching moment through an angle-of-attack sweep), with CSV files in a logs folder
- **Failure log** (L): every break, crash and jam explained, for example "Steel shaft (part 12) broke: 412 MPa at its joint, past steel's 400 MPa limit, turning at 4,200 rpm"
- **Looks**: a jointed character that runs, swims and sits; drawn textures for every material (wood grain, weaves, brushed metal, brick...); see-through glass, acrylic and diamond tinted by their colour; a moon with seas, craters and phases
- **Fixes**: ring gates in races count reliably; caves are sealed so you can't fall through; spinning parts were capped at 450 rpm by the physics engine, now about 4,800 rpm

Working now:

- **The map: Flathead Lake, Montana, at true size**, built from real elevation data. You start on Wild Horse Island, with the build pad and hangar on the flat bench above Skeeko Bay. See [The map](#the-map).
- A 64 m × 64 m build pad with a 0.25 m grid (256 × 256 cells, 128 cells high)
- A jointed low-poly character who walks, runs, swims and sits, and steps up ledges two blocks high, with a camera that scrolls from first person out to a wide third-person view
- A steel hangar behind the start point (56 × 40 m, 15 m to the eaves), with exposed I-beam frames, roof trusses and cross-bracing inside and a 44 m roller door facing the build pad. The **Open hangar** button at the top of the screen rolls the door up and back down.
- Sitting: walk up to a seat and press E to sit in it, Space to stand up
- **Respawn** (button at the top, or P) puts you back in front of the hangar from anywhere, at full health
- **Health and the replay.** You can be hurt by crashes, falls, blasts, lava and turns past 20 g, and you heal slowly. Key **0** (once something is spawned) replays the last 30 seconds from a camera that follows what you were riding; a big crash plays it on its own, and so does dying, after which you come back at the hangar. See [Health and the replay](#health-and-the-replay).
- **Weather, seasons and disasters** (the **Weather** button): rain, thunderstorms with lightning, snow, fog, gusty wind that every wing and body feels, waves on the lake that boats ride, a year of seasons every 10 game days, and tornadoes, hurricanes, tsunamis, earthquakes and a volcano. See [Weather and disasters](#weather-and-disasters).
- **Races and cargo runs for cash**: air races from 100 to 500 m/s at five airports and car races on the highway at three towns, against rivals who boast when you get close; cargo to fly between any two airports. See [Races, cargo and cash](#races-cargo-and-cash).
- **Traffic**: cars on the highways near you and light planes flying between the airports
- **Six caves** with tunnels wide enough to drive down into huge caverns and deeper crystal caverns below them
- **The Polson bridge rebuilt big**: a cable-stayed bridge over the Flathead River with two 72 m towers and a deck that humps 16 m over the water
- **The stress view** (key 9): every part coloured by its load, blue to red at breaking point; overloaded parts break off
- **Sub-assemblies** (7): save a selection (a wing, an engine pod) and drag it into any build
- **New parts**: graph screen (plots up to four signals, on the part and on your screen), electromagnet, winch and hook, and coupler (with fuel transfer for mid-air refuelling)
- Top speed for bodies raised to 750 m/s (it was the physics engine's 500 m/s)
- **A title screen** when the game starts (Play, Parts guide, Settings, Quit), and a **pause menu**: Esc (once the cursor is free; in first person the first Esc frees it) pauses the game with Resume, Parts guide, Settings, Back to the build pad, Title screen and Quit.
- **Settings** (button at the top, or from the menus), in four tabs, saved between runs. *Display:* frame rate (VSync, a limit from 1 to 240, or unlimited), resolution (50 to 100%), edge smoothing (off, 2×, 4×), shadows, tree distance, frames per second on screen, and quick presets for a laptop or a desktop. *Sound:* master, effects, machines, wind and nature, and clicks. *World:* day and night, always day or always night, and jump to a time. *Controls:* every key.
- **The parts guide** (F1, or the Guide button): a page for every one of the 78 parts saying what it does, how to use it and where its limits are, with its default size, every setting (units, default and range) and every input and output, plus pages on how welding, signals, fluids, flying, water, damage, the map and performance work. Search finds parts by name or by anything on their page.
- **Sound.** Guns, cannons, explosions and buildings coming down; motors, propellers, jets, rockets and thrusters that rise in pitch and volume as they work harder, heard from where they are; a pop for every firing of a combustion cylinder; wind that rises with your speed; birds by day and crickets at night; clicks and knocks for the interface and for placing and removing parts. Every sound is made from scratch by `tools/make_sounds.py`, so nothing was downloaded.
- A mini map in the top-right corner, north up, drawn over the real lake, with the islands, airports and buildings labelled. It zooms out as you speed up, from 600 m across standing still to 12 km across in a fast plane.
- Grass round the pad, and about 600,000 pines across the islands and the land inside the wall, built near the camera as you go
- All five tools: Place, Delete, Config, Transform and Paint
- A parts menu that stays out of the way: category tabs up the left edge, with the parts list opening beside them only while a tab is open
- A placement ghost that shows the part's own X, Y and Z axes in red, green and blue, so you can see which way it faces as you turn it
- **Basic Spawn:** the build is welded into rigid bodies that fall under gravity, collide, and can be pushed around by the character. Hinges turn.
- Twenty-two shapes in three groups. Basic: block, wedge, triangle wedge, cylinder, sphere. Structural: half block, plate, post, rod. Advanced: corner wedge, inverse corner, pyramid, cone, tapered cylinder, hemisphere, half cylinder, convex curve, concave curve, arch, ring, pipe, torus.
- All eighteen mechanical parts work once spawned: motor, servo, door hinge servo, hinge, ball joint, bearing block, piston, solenoid, spring, gear, bevel gear, rack, belt pulley, crankshaft, wheel, linkage bar, clutch and brake
- All four combat parts work once spawned: machine gun, large cannon, ammo generator and explosive block. Parts have health, and a body that loses parts breaks into separate chunks.
- **All twelve logic parts work once spawned** (see [Logic and sensors](#logic-and-sensors)): input, boolean gate, number logic, PID controller, PWM generator, speed, altitude, attitude and distance sensors, impact detector, light panel and vanish block
- **The propeller and lift-gas tank work.** A propeller on a motor pulls along its spin axis according to its speed, blade count and pitch, and loads the motor in return. A lift-gas tank lifts straight up by its setting per block, scaled by its Amount input, and weakens as the air thins.
- **The fluid and engine parts work** (see [Fluids and engines](#fluids-and-engines)): fuel tanks, pumps, valves, pipes, hydraulic and gas cylinders, pressure tanks, combustion cylinders for engines you build yourself, jet engines from a compressor, combustor, turbine and nozzle, fuel-fed thrusters and solid rockets
- Twenty-nine materials with real densities, from foam to gold, plus free choice of color, and one ideal material, **Frictionless surface**: nothing grips it, and once spawned it cannot be moved or damaged
- Resizing any part in steps of 0.005 block (1.25 mm), with live volume, mass and health
- Total mass and a center-of-mass marker for the whole build
- Saving and loading builds as shareable text files
- Undo and redo for every change, up to 100 steps back
- Signal linking in the Config tool: connect any part's input to another part's output, with lines showing the links. Links are stored and saved now and carry signals once Spawn and Logic are built.
- Settings for every functional part in the Config tool: motor torque and speed, piston lengths, speed and easing, gear teeth, light color, blast radius and so on. They are stored and saved now and take effect once Spawn is built.

### Health and the replay

You have 100 health, shown low in the middle of the screen. Hard knocks hurt: a change of speed faster than 20 g averaged over 50 ms drains it at 40 health a second per g over, so a fall of about 20 m or a crash at about 25 m/s hurts badly, and a fall of 60 m or a crash at 35 m/s kills. A long turn past 20 g hurts too. Blasts hurt out to half again their radius, and lava and lava bombs burn. Health comes back at 4 a second once you have gone 6 seconds unhurt. The wind pushes on you on foot: you stagger in a gale and a tornado picks you up. Settings → World can turn hurting off.

The last 30 seconds of every spawned body and of you are always being recorded, 30 times a second. Press 0 once something is spawned to play them back with the game paused: drag to turn the camera, wheel to zoom, Restart, Speed (1x, 2x, 0.25x, 0.5x) and Skip (or Space or Esc). Parts that broke off show whole until the moment they broke. A crash that costs 35 health in a moment while you ride plays the replay on its own; dying plays it and then puts you back at the hangar, and loses any race.

### The stress view and structural failure

Key 9 while spawned colours every part by its load: blue easy, through green and yellow, to red at its breaking point; the left of the screen shows the most loaded part. Each part carries its weight and its share of the body's acceleration and turning, plus the thrust, lift and contact forces put straight on it; the parts form a tree out from the heaviest part near the centre of mass, each joining by the widest weld it has to the tree so far, and each passes its load through the face it shares with the next, as stress = force ÷ area + bending moment ÷ section modulus. Strengths are real: balsa 10 MPa, wood 40, aluminium 270, steel 400, titanium 880, carbon fibre 600, Kevlar 1,500. With structural failure on (Settings → World), a part past its strength for two checks in a row breaks off.

### Weather and disasters

Open the Weather window with the Weather button. On Auto the weather changes every few minutes, by season: clear, cloudy, rain, thunderstorm (lightning, and thunder heard at the speed of sound), snow or fog. You can set it, set the season, or set the wind's speed and direction yourself.

- **Wind** blows everywhere with gusts and grows with height (the 1/7 power law). Wings, propellers and every body's outline feel the air's speed relative to them.
- **Waves** grow with the wind: four swells travelling with it, the same in the water you see and in the buoyancy, about 1 m high at 10 m/s and up to 3.5 m.
- **Seasons:** a year lasts 10 game days. The snow line comes down from about 2,350 m in summer to the lake in midwinter, the grass goes gold in autumn and brown in winter, and some trees turn yellow.
- **Tornado:** forms a few kilometres away and wanders your way for about three minutes; 95 m/s winds round its core, air drawn in along the ground and a strong updraft, so it drags cars in and lifts them, and smashes the buildings and towers in its path.
- **Hurricane:** four minutes of 46 m/s winds, driving rain and the biggest waves.
- **Tsunami:** an earthquake under the lake far out, then a 14 m wave spreading at 55 m/s that lifts and carries boats and runs up the shore.
- **Earthquake:** the ground shakes; loose things hop about.
- **Volcano:** the tallest mountain inside the wall (2,063 m, west of Lakeside), its summit hollowed into a glowing crater. When it erupts it rumbles, blows, throws glowing lava bombs that burst where they land, sends six rivers of lava down the steepest ground, and its ash darkens the sky for kilometres.

With random disasters on (Settings → World), one strikes on its own every 20 to 40 minutes, announced with where it is.

### Races, cargo and cash

People stand under signs at every airport, and beside the highway in Polson, Bigfork and Lakeside. Walk up and press E.

- **Air races:** Rookie Loop at Wild Horse Island (rivals at 100 m/s), Island Hopper at Polson airport (200), Lake Circuit at Bigfork airport (300), Mountain Gauntlet at Somers Mountain airport (400) and Speed Demon at Lakeside Ridge airport (500). Pick one of your saved builds: it is put on the runway, you are sat in it, and after a countdown you race three rivals through a loop of rings in order and back over the airport. The next ring is yellow with a beam of light over it; the last is green.
- **Car races:** the same on the highway, through gates every 600 m: Polson (34 m/s), Bigfork (48) and Lakeside (65).
- **Rivals** fly or drive a smooth line at their own top speed, slowing for turns tighter than they can take. Get close and one boasts in a big bubble and speeds up by up to 20 m/s for a few seconds.
- **Prizes:** first wins the race's prize, second half, third a quarter; best times are kept. F2 gives up; dying loses.
- **Cargo runs:** from any airport to any other, a light, medium or heavy crate. Carry it however you like (a cargo bay, a magnet, a winch hook) and set it down gently in the green ring at the other end. Pay by distance and weight, half again if quick; a hard knock smashes the crate.

Cash and best times are kept in the user folder (`profile.json`).

### Fluids and engines

Fluid parts that touch face to face join into a **network**: tanks, pipes, pumps, valves, cylinders and engine parts. A valve that is closed splits the network there (Open input, Amount over 0, or "Open with no input"). A pump runs at its max flow × Rate (−1 to 1; full if Rate is not linked) while On is on (always, if On is not linked). What a network does depends on what is in it:

- **Fuel.** A fuel tank holds its volume in fuel (34 MJ/L and 0.75 kg/L, like petrol, unless you change them), starting at its fill. It weighs its shell (15% of a solid block) plus its fuel, so it gets lighter as fuel burns and the center of mass moves. Level is out in %. Combustors, combustion cylinders (through a pump) and thrusters with "Runs without fuel" off take their fuel from the tanks in their network, and stop when it runs out.
- **Hydraulics.** A fluid cylinder set to hydraulic oil is moved by the pumps in its network: the rod goes out at the pumps' flow over the cylinders' area (back in with a negative Rate), pushing with up to the pumps' max pressure × its area. With the pumps stopped, the oil is locked and the rod holds where it is (up to 20 MPa). Two cylinders on one pump share the flow.
- **Gas.** Pressure tanks and fluid cylinders set to gas share one pressure, by the ideal gas law. A gas cylinder pushes its rod out with (pressure − outside air) × area, so it is an air spring: push the rod in and the pressure rises. A pump in a gas network pumps outside air in, up to its max pressure (or lets it out, run backward).
- **Combustion cylinders** are the heart of a piston engine you build yourself: link the rod to a crankshaft with a linkage bar (ball joints), put a pump and a fuel tank touching the cylinder (or joined to it by pipes), and turn the crank to start it (a motor makes a good starter). The pump sends fuel in, at most what one cylinder of air can burn. With "Fires by itself at the top" on, it fires just past the top of its stroke; or link Spark to your own timing (number logic's Modulo turns the crank's angle into 0 to 360°, and Between makes a firing window). The fuel burns at once and the pressure jumps; the gas expands as the rod goes out, pushing the crank round, then the cylinder breathes out and in near the bottom and squeezes the fresh air (9 to 1) on the way back up. The pump's Rate is the throttle. A cylinder 0.6 blocks across and 0.6 long burns about 0.3 mL a firing, so a pump max flow of about 0.02 L/s per cylinder gives full throttle at a few thousand rpm. Pressure out is in kPa.
- **Jet engines.** A compressor, a combustor, a turbine and a nozzle in one network (with a fuel tank) make a jet. The combustor burns its max fuel flow × Fuel rate (full if not linked). The spool winds up over a few seconds as fuel flows; air flow is air density × the compressor's face area × 100 m/s at full spool; the heat speeds that air up at the ideal efficiency for the compressor's pressure ratio, and the thrust (air flow × the speed the jet gains) comes out of the back of the nozzle, pushing along its −Z like a thruster. Thrust falls as you fly faster. Compressor and turbine put out the spool speed in rpm, the nozzle its thrust. A compressor 4 blocks across with 0.1 L/s of fuel makes about 16 kN standing still; give it 1 L/s for about 50 kN.
- **Solid rockets** light when Ignite switches on and push along −Z with their thrust for their burn time, getting lighter as the propellant burns, then go out. "Never burns out" keeps them going forever.
- **Fuel-fed thrusters** (Runs without fuel off) burn fuel from their network in proportion to thrust, about 0.5 L/s for each 1,000 N.

### Logic and sensors

Link outputs to inputs with the Config tool. On/off signals are 1 and 0; any number other than 0 counts as on. Signals pass through a chain of up to four gates in the same physics tick.

- **Boolean gate:** AND, OR, NOT (of A), XOR, NAND and NOR. **Latch:** A switches it on, B switches it off. **Timer:** when A switches on, the result stays on for the timer length.
- **Number logic:** an unlinked B uses the Constant setting, so "Add" with only A linked adds the constant. Add, Subtract (A − B), Multiply, Divide (A ÷ B, 0 if B is 0), Absolute value (of A), Min, Max, Clamp (A between B and C), Compare (on if A > B), Select (B if A is on, else C), Map range (A from B…C onto 0…1), Modulo (A wrapped into 0 up to B), Between (on while A is between B and C). "Comparison is true" is on whenever the result is not 0.
- **PID controller:** output = Kp × error + Ki × its running total + Kd × its rate of change, where error = setpoint − measurement, held between the lowest and highest output. The running total stops growing while the output is held at a limit, and the rate is taken from the measurement, so a sudden change of setpoint does not jolt it.
- **PWM generator:** a square wave. Output is on for the duty cycle's share of every cycle and off for the rest, at its frequency (up to 120 Hz; the physics runs at 240 steps a second, so higher would be meaningless). Duty (0 to 1) and Frequency (Hz) inputs override the settings while linked, and Enable (on if not linked) stops it with the output off. Phase puts out where it is in the cycle, 0 to 1, as a sawtooth. Link Output to a thruster's On, a motor's direction or a light to pulse them; link a number (a PID's output, say) to Duty to vary the share of time on.
- **Speed sensor:** m/s. **Altitude sensor:** metres above sea level (the lake is at 881 m). **Attitude sensor:** pitch (nose up positive), roll (right side down positive) and yaw (compass heading, 0 north, 90 east) in degrees, plus each rate in degrees per second, all of the sensor's own forward (−Z) and up (+Y).
- **Distance sensor:** metres from the sensor straight ahead along its −Z to the first part, building, ground or water, up to its range; it reads the range if nothing is there.
- **Impact detector:** puts out its acceleration in g (0 at rest or in steady flight) and switches on for its signal length whenever that passes its trigger level.
- **Light panel:** glows in its color, or in the Red, Green and Blue inputs (0 to 255) if linked, while On is on (always, if On is not linked), and lights up what is around it.
- **Vanish block:** disappears and stops being solid while Vanish is on. With "Comes back when the signal ends" off it stays gone.
- **Propeller:** Speed out is in rpm.

**Example: an autopilot that holds the nose level.** Put an attitude sensor anywhere on the plane with its blue Z arrow pointing back toward the tail and its green Y arrow up. Add a number logic block set to Constant 0 (the pitch to hold, in degrees) and a PID controller. Link the PID's Setpoint to the number block's Result, its Measurement to the sensor's Pitch, and the elevator servo's Angle to the PID's Output. Set the PID's lowest and highest output to the elevator's travel, say −20 and 20, and the servo's speed to about 300°/s. Start with Kp 1, Ki 0, Kd 0. If the nose runs away instead of coming back, make all three gains negative. Raise Kp until it holds but bobs, add Kd (about a third of Kp) to calm the bobbing, then a little Ki (about a tenth of Kp) to take out any steady offset. Keys linked to the servo's "Go to positive/negative target" still override it, so you can fly by hand and let go. **To hold an altitude,** add an altitude sensor and a second PID in front of the first: Setpoint from a number block (the height above sea level to hold), Measurement from the altitude sensor, output limits −10 to 10 (degrees of climb or dive), Kp about 0.05, Kd about 0.1, and link its Output to the first PID's Setpoint in place of the constant.

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
| Esc | Free the cursor (first person); with the cursor free, pause. Closes the map, guide and settings. |
| F1 | Parts guide |
| M | Open or close the full map. Scroll to zoom, drag to move it, click to set a waypoint, right-click to clear it. |
| P | Back to the build pad |
| 1 to 5 | Place, Delete, Config, Transform, Paint. Press the same key again to put the tool away. |
| 6 | Scale: pull the handles to resize the selection (Shift for whole blocks, Alt for both sides) |
| 7 | Sub-assemblies menu |
| G | Grab the selection and move it with the mouse; Esc puts it back |
| 8 | Inspector (while spawned) |
| 9 | Stress view (while spawned) |
| 0 | Replay the last 30 seconds |
| F3 | Performance overlay |
| L | Failure log |
| J | Missions board |
| B | Bird guide |
| C | Camera (wheel zooms, F changes the filter, click takes the photo) |
| F | Refuel, standing at a pump |
| Ctrl+Z / Ctrl+Y | Undo / redo (also the Undo and Redo buttons, bottom right) |
| Left click | Use the current tool |
| R / T / Y | Turn 90° about X / Y / Z: the part you are about to place, or the Transform selection. The red, green and blue buttons at the bottom left do the same. |

### Controller

An Xbox or PlayStation controller works alongside the keyboard and mouse.

| Controller | Action |
| --- | --- |
| Left stick | Walk |
| Right stick | Look around |
| L3 (press the left stick) | Run |
| R3 (press the right stick) | First or third person |
| A / Cross | Jump |
| Y / Triangle | Sit in the nearest seat |
| View / Create | Stand up from a seat; on foot, spawn the build or go back to building |
| Menu / Options | Pause; the D-pad and A move through the menus, B goes back |
| D-pad up / down | Zoom, on foot |

Seated, every other button, stick and trigger is free for the build's **Controller input** blocks (Logic): pick the control, then Hold, Toggle or Pulse for buttons; sticks and triggers give a number from −1 to 1 (0 to 1 for triggers) times "Value at full push", after the dead zone and the response curve.

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

The bottom-right corner shows which build of the game is running (for example "Build 23"). While building it also shows how many parts the build has, and while you sit in a moving vehicle how fast it is turning (°/s). Beside the speed it shows the g-force the character feels: 1 g standing still, 0 g in free fall, more in a hard turn or pull-up, which helps to check that the newest copy is the one open.

This is the basic version. What it does so far:

- **Welding.** Parts whose bounding boxes share a face (or part of one) or overlap are welded into one rigid body. Parts that only meet along an edge or at a corner are not. Separate groups become separate bodies.
- **Mass.** Each body has the combined mass and center of mass of its parts, from their real volumes and densities. Its friction is the mass-weighted average of its materials.
- **Gravity and collisions.** Bodies fall, collide, stack and tip over. Each body's inertia comes from the real mass and place of every part in it, so a heavy engine in the nose makes a plane slow to turn.
- **Friction** against the ground is the geometric mean of the two coefficients, √(μ × 1): every body is given √μ of its materials, and the world's surfaces more than any body has, so the physics engine (which takes the lower) picks the body's. Between two bodies it takes the lower √μ.
- **Overlaps count once.** Parts of one material that overlap share their overlap: the later part gives up its share of the volume, so mass and center of mass count it once.
- **Crash damage.** A body whose speed changes by more than 20 g, averaged over 50 ms (which irons out engine shake), damages every part in it by 0.05 HP per kg of that part per g over, per tick: heavy, weak parts break first. Off in Settings → World.
- **Far-away builds park.** A fleet vehicle or the pad's build more than 3 km from you freezes where it is, keeping its speed, and carries on when you come within 2.5 km.
- **Air drag on every body.** For each of its own three axes, a body's outline seen along that axis (in quarter-block cells, overlaps counted once) catches the air: force = ½ × air density × 1.0 × area × speed², acting at the middle of that outline, so a body with more outline behind its centre of mass turns into the wind like a dart. Aero panels and propellers are left out of the outline because they work out their own drag.
- **The fleet.** The **Fleet** button at the top spawns any saved build out into the world, a few metres in front of you and facing your way, as a vehicle of its own with its own logic, engines and guns. It stays, working, while you build something else on the pad; sit in its seats like any other. Despawn them one by one or all at once. Up to 8; they show as green squares on the mini map and full map.
- **Pushing.** The character has a mass of 70 kg. Walking into a body pushes it with a force equal to the character's momentum toward it (mass × closing speed) handed over across a quarter of a second, but never harder than the feet can grip: grip × weight, about 687 N on the ground and next to nothing on ice. Friction with the ground decides the rest. A light body slides away, a heavier one moves slowly and holds you back to its speed, and one whose friction is greater than the push does not move at all. Every push is a force in newtons from the game's own code; the physics engine itself never shoves a body out of the character's way.
- **Weight and grip.** A body you stand on carries your weight, and feels the reaction of your feet: speed up, slow down or push on something while standing on a loose body and it is pushed the other way. The character changes speed only as fast as its grip allows (grip × g), so it takes a moment to get going on the ground, is slippery on ice, and cannot change speed at all on a frictionless surface.
- **Seats** work the same as on the pad: E to sit, Space to stand up.
- **Ladders** can be climbed: walk into one (or hold Space against it) to go up at 2 m/s, stand still to hang on, walk away to let go. While its Stowed input is on it is hidden and not solid.
- **Reload gate:** the parts built on its rail (its own +Y face, found the way an offsetter finds its load) are welded to it. Release lets them go as a body of their own, moving as they were (plus the push-off speed, straight out from the rail, with the build pushed back by as much); after the reload time (or what its Reload time input says, while linked) an identical copy appears on the rail, linked to the same controls as the first, unless the last one hasn't cleared the rail yet (it waits) or the reloads are used up. Explosives on the rail can't go off, and stay safe for the set time after letting go. A payload once let go is passed by its own build's blasts, so dropped bombs don't set each other off.
- **Hinges** work. A hinge splits across its middle into a base half and a top half, joined by the pin along its own X axis. Each side welds to whatever touches it, so what is attached to the top swings relative to what is attached to the base. Something that touches both sides, such as a block standing beside the hinge, welds to the side it shares more area with, and to the base if they are even. The hinge's settings apply: angle limits (off by default, so it turns freely) and friction torque. The two bodies a joint connects do not collide with each other, so use the angle limits to stop it where it should stop. If both sides of a joint end up welded to the same body through other parts, it cannot turn, and the spawn message says how many joints are locked that way.
- **Motors and servos** work the same way: the housing is the base and the output on top is the side that turns. Whatever touches the top face turns with it. A **motor** turns about its own +Y at up to its max speed, with up to its max torque; link Clockwise or Counterclockwise to input blocks, or link Speed to a number from −1 to 1. A **servo** also turns about its own +Y, and a **door hinge servo** swings its upright leaf about the edge it shares with its base plate. Link Go to positive target and Go to negative target to input blocks, and the servo moves to those angles at its set speed and returns to its default angle, or holds, when neither is on; or link Angle to a number of degrees. Angles are zero as built, and positive is counterclockwise seen from the top looking back at the base. Each drive works through its joint: the physics engine holds the turning speed the drive asks for as part of solving the joint, with at most the drive's max torque, so a servo holds its angle rigidly however light or heavy the thing it turns, and the base feels the opposite torque.
- **Thrusters** push along their own −Z with the thrust set in Config. With nothing linked a thruster runs flat out from the moment of spawning. Link its On input to an **input block** (Config tool, Signals) to run it from a key, or link Throttle to an input block set to "Number from two keys" to drive it forward and back. Key binds work only while you are sitting in a seat. A running thruster shows a glow.
- **Aero panels** make lift and drag. Each panel takes the air's speed at its own center, finds its angle of attack, and applies lift = ½ × air density × speed² × area × lift coefficient at right angles to the airflow, and drag along it. The lift coefficient is 4.0 per radian up to the 15° stall and follows a flat plate (sin 2α) beyond it; the drag coefficient is 0.01 + 2 sin²α. A panel is flat, so it makes no lift at zero angle of attack. The **dragless** panels make the same lift with no drag at all. Air density is 1.225 kg/m³ at the ground and thins with height.
- **Every other mechanical part** comes apart into pieces held by a real joint, and each piece welds to whatever touches it:
  - **Ball joint:** the top swivels on the base. Settings: an angle limit, and "carries rotation", which stops it twisting so it passes turning through.
  - **Bearing block:** the housing welds by its four sides and the shaft through it by its two ends (along its own Y). The shaft turns freely, against its friction torque.
  - **Piston:** the rod end on top slides out along its own +Y. Link Extend to run out to the target length, or link Length to a number of blocks; it moves at its set speed and easing with up to its max force. Outputs its length. In sensor mode it is a load cell instead: it holds its length with a very stiff spring and puts out the pressure on it in kPa.
  - **Solenoid:** link On and the top snaps out by its stroke with its set force, and back when off.
  - **Spring:** the two plates are pushed apart below the rest length and pulled together above it, by stiffness × stretch, less damping × speed. The coils stretch to match.
  - **Crankshaft:** the journals weld by the two ends (along its own X) and the webs turn between them. For a working engine linkage, join a linkage bar to the webs. Its throw radius and rod length give two more outputs: the rod end's distance from the axis, r cos θ + √(L² − r² sin² θ), and "Near the top" (within 15° of top dead centre), handy for spark timing.
  - **Wheel:** set to spin freely (the default), the hub welds by the ends of its axle (along its own X) and the round tyre turns on it, against its friction torque. Turn spin freely off to bolt a solid wheel to a motor.
  - **Linkage bar:** a bar with a joint at each end (ball joints, or hinges about Y or Z, as set). Each end welds to what touches it.
  - **Clutch:** the two plates turn together with up to the max torque and slip past it. Link Engage, or Amount (0 to 1) to grip part way.
  - **Brake:** the caliper welds by its +X face and the disc by its two ends (along its own Y). Link Brake, or Amount (0 to 1), to hold the disc still with up to the max torque.
  - **Gears, bevel gears, pulleys and racks** are fixed to what they touch, like any block. Spur gears whose shafts are parallel, level and whose rims touch turn together in the ratio of their teeth; bevel gears do the same with shafts at right angles. Pulleys with the same belt number, parallel shafts and level with each other turn together in the ratio of their sizes, with the belt drawn between them (belt 0 means no belt). A gear train whose ratios disagree round a loop jams, and the spawn message warns about it. A gear sitting on a rack's teeth with its shaft across the rack drives the rack along. Mount gears on a motor, bearing or wheel axle so they have something to turn on.
- **Health and damage.** Every part has health = mass × material strength (the Config tool shows it). A part whose health runs out disappears, and if what is left of its body is in separate pieces, each piece becomes a body of its own and flies off with the speed it had.
- **Machine gun:** fires along its own −Z while its Fire input is on, at its fire rate. Each round is an instant line out to its range and does 4 HP to the first part it hits, with a small push, and the gun feels the recoil.
- **Large cannon:** fires along its own −Z. Its size sets the shot: the bore is a fifth of its smaller cross size, the shell is three bores long and made of the projectile material, and the propellant pushes it down the barrel at 100 MPa, so muzzle energy = 100 MPa × bore area × barrel length (the Config tool shows the numbers). Shells fly under gravity and do 1 HP per kJ they carry on impact. A shell goes through any part it destroys, slowed by the energy that took. One shot per 0.5 s per metre of barrel, with recoil.
- **Ammo generator:** makes its set rate per second up to its storage, starting empty, and gets heavier as it fills (25 g per machine gun round; a cannon shell weighs what the heaviest cannon linked to it fires). Turn off a gun's Unlimited ammo and link its Ammo supply input to a generator of the right type, and each shot takes one.
- **Explosive block:** goes off when its Detonate input is on, or when it is destroyed. Every part within the blast radius takes 1000 HP per metre of radius at the centre, falling to nothing at the edge, and is pushed away by 1 N·s per HP. An explosive caught in a blast goes off one tick later, so chains of them ripple.
- A body that contains an **anchor block**, or any part made of the **Frictionless surface** material, is fixed in place. A **dynamic offsetter** moves and turns everything built on its top face (its own +Y), by its shift and turn settings along its own axes, at spawn, and holds it welded there; then it is invisible and has no collision.

Not yet: engines, fluid parts and logic blocks are welded solid and do nothing. Belts are not drawn. A piston's Pressure output reads 0, and the crankshaft's throw and rod length settings are not used yet (build the linkage from linkage bars). There is no drag on anything but aero panels yet. Hollow shapes (arch, ring, pipe, torus, concave curve) collide as their filled-in outline while spawned.

## To runway

The blue **To runway** button beside Spawn (or **Take the build to a runway** in the pause menu, for the controller) takes the whole build to the start of the nearest asphalt runway, spawning it first if it isn't already. It is put down level, the way it was built, facing down the runway the way its first seat faces (or its thrusters push, with no seat), with its lowest point just above the ground and everything stopped: no crash damage, stress or impact detectors go off from the sudden stop. Press again while still parked at the start for the next runway, in order of distance from the hangar. Seated, you come along; on foot, you are put on the runway in front of the build.

## The map

The world is Flathead Lake in northwest Montana, at true size: 44 km long and 25 km wide. Its real shoreline and every island come from USGS elevation data. The edge of the world is a straight-sided rectangle, 29 km east to west and 50 km north to south, square to north and 2 km beyond the lake's furthest reach on every side, so it takes in a stretch of the rivers too. It is a stone wall with an unseen barrier above it up to 12 km, so nothing can fly out, and its corners are all right angles, so nothing snags on it. The land beyond the wall is still drawn, out to the mountains.

- **Wild Horse Island** is where you start. The pad and hangar sit on the flat bench above Skeeko Bay, near the north centre of the island, 901 m above sea level and 20 m above the lake. The island is Palouse grassland with pine on the north-facing slopes.
- **Wild Horse Island airport:** a 1,200 m × 30 m asphalt runway running north and south, west of the pad, with a 2 % slope, a parking apron, a hangar and a tower. Its runway is at 90° to Melita's.
- **Melita Island:** a bush-plane strip as long as the real island allows (803 m of gravel, east and west), starting at a timber landing on the west shore. The island is thick with trees except along the strip and in the open middle, where the Camp Melita lodge serves as the terminal. The camp's big main dock is where the real one is, on the sheltered south face: a wide walkway on rock-filled cribbing with finger piers, a T-head and the camp's fleet of pontoon arks, sailboats, fishing boats and canoes.
- **Polson airport**, on its real runway: 1,278 m of asphalt at the south end of the lake, 896 m above sea level.
- **Six mountain airports**, 900 m asphalt runways high in the hills inside the wall (1,400 to 1,530 m above sea level), on the flattest long stretches of ground the bake could find, each with an apron, hangar and tower.
- **Cromwell Island:** the estate as the sale listing describes it, built much larger than life. The unfinished villa stands at the centre of the island: a 16th-century French château of battered travertine with terracotta tile roofs, four round towers with conical roofs, mahogany windows and twin staircases curving up to the entrance, facing east toward Wild Horse, with a tower crane still behind it. A gravel road runs from the five-slip dock on the west shore (a 70 ft yacht and the estate's 60 ft barge moored there) past the guest villa to the house. A 1.3 km gravel airstrip crosses the gentler south half of the island.
- **Airstrips on the other islands**, gravel, each as long as the island's gentle ground allows and graded no steeper than 6 %: Bird (683 m), Bull (609 m), Cedar (425 m), Shelter (366 m) and Little Bull (295 m). **Helipads** on the islands too small for a strip: Dream, Rock, Mary B, Douglas, Goose and Invitation.
- **Shelter Island mansion:** a modern lake house of stone, timber and glass beside the island's strip.
- **The aircraft carrier**, three times the size of a real one: a kilometre-long flight deck, 230 m wide and 54 m above the water. It is moored at a random spot on open water each time the game starts. Check the mini map to find it.
- Every other island is at its real place: Dream, Shelter, Cedar, Rock, Mary B, Douglas, Goose, Bird, Bull, Little Bull and Invitation.
- **Small airports by the towns:** every town without one has a 700 m × 20 m paved runway on the flattest open ground near it, clear of its buildings and roads, with an apron, hangar and tower: Bigfork, Lakeside, Somers, Rollins, Dayton, Elmo, Big Arm, Woods Bay, Yellow Bay and Finley Point.
- **Wizard towers:** six enormous round stone towers with pointed purple roofs and gold finials, at random places on dry land each time the game starts (find them on the mini map). Each is 190 to 240 m across (wider than the Cromwell château) and 430 to 580 m tall to the top of its wall, with the roof 250 to 310 m more. They can be destroyed: see [Destruction](#destruction).
- **The real towns**, from OpenStreetMap: Polson, Bigfork, Lakeside, Somers, Rollins, Woods Bay, Big Arm, Elmo, Dayton, Finley Point and Yellow Bay, with every mapped road and building inside the wall (about 4,000 buildings and thousands of kilometres of road). Roads are drawn on the ground: asphalt highways with a yellow centre line, side streets, and brown gravel tracks. Buildings stand on their real outlines at their real or estimated height and are solid, so you have to fly over them or drive round them. Bridges over water, such as US 93 at Polson, are solid decks you can drive across. The town names show on the mini map. Map data © OpenStreetMap contributors, ODbL.
- **Day and night:** a whole day takes 20 minutes, 10 of daylight and 10 of night. The sun rises in the east, crosses the southern sky and sets in the west in an orange glow; at night the moon follows it across, the stars come out, and the runway lights come on at every airport. The time is shown at the bottom right. Settings can hold it at day or at night, or jump to dawn, noon, dusk or night.
- **The full map** (M) shows the whole lake and the land round it with the towns, islands, airports and wizard towers. Click it to set a **waypoint**: it shows on the mini map (at the edge, with a line, when it is out of sight) and its distance and compass bearing appear at the bottom right.
- **Altitude** on screen is real, in metres above sea level, and the air thins with real altitude, so wings lose a little lift at the lake's 881 m.

### Destruction

Every building in the towns and every wizard tower can be shot or blown down. All of it is put back when you press Build.

- **Buildings** have health for the space they enclose: 2 HP per cubic metre for wooden houses, sheds and barns, 4 for brick (schools, churches, apartments, hotels), 6 for concrete (shops, warehouses, industry), up to 150,000. A typical house has about 1,000 to 3,000 HP. Brought to zero, a building falls to a low heap of rubble in a cloud of dust.
- **Wizard towers** are built of stone blocks, 24 round and 18 high, each with about 4,000 to 6,000 HP (0.6 HP per cubic metre of stone). A destroyed block leaves a hole. When a ring of the tower loses half its blocks it can no longer carry the weight above it: that ring and everything over it break loose, a piece per ring and one for the roof, and come crashing down, tipping toward the side that was shot away. Fallen pieces turn to fixed rubble once they stop moving.
- Bullets do 4 HP, cannon shells 1 HP per kJ they carry (a shell goes on through anything it destroys), and blasts their usual damage falling off with distance.

**Water.** Spawned builds float. Each part pushes aside water equal to its own solid volume (its mass over its material's density), so wood floats and steel sinks; and air sealed inside a build (empty grid cells that cannot be reached from outside without passing through a part) floats it too, so a closed steel hull floats as a real one does. If any part of a hull is destroyed, its sealed air floods. Water also drags on whatever moves through it. The character swims, with head and shoulders out of the water; Space swims up. The lake bed is shaped from the distance to shore, down to the real 113 m deepest point.

**Re-centring.** Whenever the character gets 1.5 km from the middle of the world, everything is moved back by whole kilometres so that positions stay small and physics stays precise anywhere on the lake. Nothing changes that you can see or feel.

**Solid ground and trees.** The ground and tree trunks are solid around the character and every spawned body (out to 200 to 320 m, and further ahead of anything moving fast). Bullets and cannon shells also stop at the ground however far away they land.

**How it is built.** `tools/fetch_terrain.py` downloads the elevation data on your own computer into `map/`. `tools/bake_map.py` turns it into the game's map in `map_data/` and writes `scripts/map_info.gd`. It resamples the data to a metre grid, levels the pad, runways, lodge and villa sites, shapes the lake bed, traces the wall and places every tree. Both scripts only need running again to change the map; their output is already in the repository. Elevation data: Mapzen Terrain Tiles on AWS Open Data, from USGS 3DEP and others.

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
| `scripts/gamepad.gd` | Reading Xbox and PlayStation controllers: names of every control, dead zones and curves |
| `scripts/spawner.gd` | Spawn: welds the build into rigid bodies, runs the machines, and handles part health |
| `scripts/combat.gd` | Guns, cannon shells, ammo generators and explosives |
| `scripts/part_library.gd` | Part shapes: meshes, collision, volume |
| `scripts/mech_models.gd` | Display models for the mechanical parts |
| `scripts/mesh_kit.gd` | Helpers that build meshes from boxes, cylinders and gear discs |
| `scripts/material_library.gd` | Materials: density, friction, strength, look |
| `scripts/part_settings.gd` | The settings each kind of part has, with defaults and limits |
| `scripts/part_ports.gd` | The signal inputs and outputs each kind of part has |
| `scripts/save_manager.gd` | Saving and loading builds |
| `scripts/hud.gd` | The on-screen interface |
| `scripts/minimap.gd` | The mini map |
| `scripts/scenery.gd` | Grass round the pad |
| `scripts/terrain.gd` | The map: ground drawn round the camera, solid ground near the character and spawned bodies, the lake and the wall |
| `scripts/forest.gd` | Every tree, drawn in 1 km squares, solid near the character |
| `scripts/landmarks.gd` | The airports, the Melita dock and lodge, the Cromwell villa and the carrier |
| `scripts/logic.gd` | Logic blocks, sensors, light panels, vanish blocks, propellers and lift-gas tanks |
| `scripts/sound.gd` | Sound: effects, machine loops, wind and nature, volumes |
| `scripts/menus.gd` | Title screen, pause menu, and the windows they open |
| `scripts/parts_guide.gd`, `parts_guide_text.gd` | The parts guide window and its pages |
| `tools/make_sounds.py` | Makes every sound in `sounds/` from scratch |
| `scripts/engines.gd` | Fluid networks, fuel, pumps, cylinders, jet engines and rockets |
| `scripts/daylight.gd` | Day and night: sun, moon, sky, stars and runway lights |
| `scripts/world_map.gd` | The full map (M) and waypoints |
| `scripts/towers.gd` | The wizard towers: placing, building, damage and collapse |
| `scripts/towns.gd` | The real towns: roads, buildings and bridges, built in 1 km squares near the camera, and buildings being destroyed |
| `scripts/origin.gd` | Re-centring the world on the player |
| `scripts/settings.gd` | Loading, saving and applying the settings |
| `scripts/settings_panel.gd` | The settings window |
| `scripts/map_info.gd` | Where the baked map data sits; written by `tools/bake_map.py` |
| `scripts/replay.gd` | Records the last 30 seconds and plays them back |
| `scripts/game_hud.gd`, `graph_view.gd` | Health, cash, announcements, windows, and graph screens drawn on screen |
| `scripts/profile.gd` | The three save slots: cash, races won, best times, missions, birds, ghosts and the clock |
| `scripts/stress.gd` | The stress view and structural failure |
| `scripts/rigging.gd` | Electromagnets, winches and hooks, couplers and fuel transfer |
| `scripts/weather.gd`, `weather_panel.gd` | Weather, wind, waves and seasons, and the Weather window |
| `scripts/disasters.gd`, `tornado.gd` | Tornadoes, hurricanes, tsunamis, earthquakes and the volcano |
| `scripts/caves.gd` | The caves: tunnels, caverns, crystals and the headlamp |
| `scripts/roads.gd` | The highway network for traffic and car races |
| `scripts/traffic.gd` | Cars on the highways and planes between the airports |
| `scripts/races.gd` | Air, car and boat races, rivals, cargo runs and the people who offer them |
| `scripts/ghosts.gd` | Recording your best run and racing it as a ghost |
| `scripts/missions.gd` | The missions board, photo jobs and the map's markers |
| `scripts/bird_data.gd`, `birds.gd`, `bird_guide.gd` | The 23 birds and their facts; flying, nesting and spotting them; the bird guide |
| `scripts/photo_camera.gd` | The camera, its filters and the photos window |
| `scripts/fuel.gd` | Fuel stations, pumps and prices |
| `scripts/damage_fx.gd` | Smoke, scorch, fuel-tank fires and coughing engines |
| `scripts/failure_log.gd` | Notes of every break, crash and jam, and the log window (L) |
| `scripts/boats.gd`, `ice.gd`, `flowers.gd` | Docks and summer boats, winter ice, spring flowers |
| `scripts/volcano.gd` | The volcano's cone, crater and lava lake |
| `scripts/assembly_menu.gd` | The sub-assemblies menu (7) |
| `scripts/inspector.gd` | The Inspector (8): links, shafts, gears and fluids drawn live |
| `scripts/perf_overlay.gd`, `profiler.gd` | The performance overlay (F3) and the timers behind it |
| `scripts/test_stand.gd` | The test stand: dyno and wind tunnel |
| `scripts/material_textures.gd` | Each material's texture scale and bumps; written by `tools/make_textures.py` |
| `tools/make_textures.py` | Draws every material texture in `textures/materials/` from scratch |
| `shaders/part.gdshader`, `part_tint.gdshader`, `part_shine.gdshader` | Building parts: textures laid on in metres, and see-through glass |
| `tools/smoke_test.gd`, `disaster_test.gd`, `race_test.gd`, `stand_test.gd`, ... | Headless tests: `godot --headless --path . -s tools/smoke_test.gd`; `tools/load_all.gd` loads every script to catch errors |
| `tools/shot.gd`, `model_shot.gd`, `material_shot.gd`, `moon_shot.gd` | Screenshots with a real renderer, for checking looks |
| `tools/build_kit.py`, `make_f14.py`, `make_b2.py`, `make_plane.py` | Write builds from code: the F-14 (`python3 tools/make_f14.py "saves/F-14 Tomcat.json"`), the B-2 (`python3 tools/make_b2.py "saves/B-2 Spirit.json"`) and the big delta plane |
| `tools/build_shot.gd` | Pictures of a build file from six sides (add `lit` for its lights on) |
| `tools/f14_test.gd`, `b2_test.gd`, `plane_test.gd`, `pad_test.gd` | Flight tests of the F-14 (ground, takeoff, air, missile, fast, reload, ladder), the B-2 (ground, takeoff, air, bomb, low, ladder; prints tick times) and the delta plane, and the controller test |
| `tools/runway_test.gd` | To runway: from build mode, seated, again for the next runway, and rolling down it |
| `tools/check_shaders.gd` | Compiles every shader and reports failures |
| `tools/find_caves.py` | Searches the heights for cave sites |
| `shaders/terrain.gdshader` | Lifts the ground to the baked heights and colours it |
| `shaders/water.gdshader` | The lake surface, its waves and a tsunami |
| `shaders/tree_crown.gdshader` | The pines through the seasons |
| `shaders/swirl.gdshader` | A tornado's funnel and its skirt of dust |
| `map/` | The downloaded elevation data |
| `map_data/` | The baked map: heights, trees, buildings, wall, mini map picture |
| `tools/fetch_terrain.py` | Downloads the elevation data (run on your own computer) |
| `tools/fetch_osm.py` | Downloads the real roads and buildings (run on your own computer) |
| `tools/bake_map.py` | Turns the elevation data into the game's map |
| `tools/towns.py` | Lays the OpenStreetMap roads, buildings and bridges on the baked ground (called by `bake_map.py`) |
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
