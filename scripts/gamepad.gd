extends RefCounted
## Game controllers: an Xbox One / Series pad or a PlayStation (DualSense,
## DualShock) pad, plugged in by USB or paired by Bluetooth. Godot reads both
## through the same standard layout, so button A on an Xbox pad is Cross on a
## PlayStation pad, B is Circle, X is Square and Y is Triangle.
##
## Everything here reads the first pad that is connected. Sticks read from -1
## to 1 with right and up positive; triggers read from 0 to 1; buttons and the
## D-pad read 0 or 1.

## The controls a Controller input block can read, in menu order, each with
## what it is: ["button", JoyButton] or ["axis", JoyAxis, sign] or
## ["trigger", JoyAxis].
const CONTROLS := {
	"A / Cross": ["button", JOY_BUTTON_A],
	"B / Circle": ["button", JOY_BUTTON_B],
	"X / Square": ["button", JOY_BUTTON_X],
	"Y / Triangle": ["button", JOY_BUTTON_Y],
	"LB / L1": ["button", JOY_BUTTON_LEFT_SHOULDER],
	"RB / R1": ["button", JOY_BUTTON_RIGHT_SHOULDER],
	"LT / L2 trigger": ["trigger", JOY_AXIS_TRIGGER_LEFT],
	"RT / R2 trigger": ["trigger", JOY_AXIS_TRIGGER_RIGHT],
	"Left stick X (right +)": ["axis", JOY_AXIS_LEFT_X, 1.0],
	"Left stick Y (up +)": ["axis", JOY_AXIS_LEFT_Y, -1.0],
	"Right stick X (right +)": ["axis", JOY_AXIS_RIGHT_X, 1.0],
	"Right stick Y (up +)": ["axis", JOY_AXIS_RIGHT_Y, -1.0],
	"D-pad up": ["button", JOY_BUTTON_DPAD_UP],
	"D-pad down": ["button", JOY_BUTTON_DPAD_DOWN],
	"D-pad left": ["button", JOY_BUTTON_DPAD_LEFT],
	"D-pad right": ["button", JOY_BUTTON_DPAD_RIGHT],
	"Left stick click (L3)": ["button", JOY_BUTTON_LEFT_STICK],
	"Right stick click (R3)": ["button", JOY_BUTTON_RIGHT_STICK],
	"Menu / Options": ["button", JOY_BUTTON_START],
	"View / Create": ["button", JOY_BUTTON_BACK],
}

## Below this much a stick reads zero, so a worn stick that never quite
## centres does not creep.
const STICK_DEADZONE := 0.15
const TRIGGER_DEADZONE := 0.04

## Set by tests to stand in for a real pad: control name -> value.
static var fake: Dictionary = {}


static func control_names() -> Array:
	return CONTROLS.keys()


## The device number of the first connected pad, or -1 for none.
static func device() -> int:
	var pads := Input.get_connected_joypads()
	return int(pads[0]) if not pads.is_empty() else -1


static func connected() -> bool:
	return not fake.is_empty() or device() >= 0


## A control's raw reading: a stick from -1 to 1 (right and up positive), a
## trigger from 0 to 1, a button or D-pad direction 0 or 1. Unknown names
## and no pad read 0.
static func raw(control: String) -> float:
	if fake.has(control):
		return float(fake[control])
	if not CONTROLS.has(control):
		return 0.0
	var pad := device()
	if pad < 0:
		return 0.0
	var spec: Array = CONTROLS[control]
	match str(spec[0]):
		"button":
			return 1.0 if Input.is_joy_button_pressed(pad, spec[1] as JoyButton) else 0.0
		"trigger":
			return clampf(Input.get_joy_axis(pad, spec[1] as JoyAxis), 0.0, 1.0)
		"axis":
			return clampf(Input.get_joy_axis(pad, spec[1] as JoyAxis) * float(spec[2]), -1.0, 1.0)
	return 0.0


## True for the sticks and triggers, which give any value in their range.
static func is_analog(control: String) -> bool:
	return CONTROLS.has(control) and str((CONTROLS[control] as Array)[0]) != "button"


## A reading with its dead zone taken out and rescaled, so it still runs all
## the way to 1, then bent by `curve`: 1 is straight, 2 gives fine control
## near the middle and full throw at the end.
static func shaped(value: float, deadzone: float, curve: float) -> float:
	var size := absf(value)
	if size <= deadzone:
		return 0.0
	var spread := (size - deadzone) / maxf(1.0 - deadzone, 0.0001)
	return signf(value) * pow(clampf(spread, 0.0, 1.0), maxf(curve, 0.1))


## A control read the way a Controller input block reads it.
static func read(control: String, deadzone: float, curve: float) -> float:
	var value := raw(control)
	if not is_analog(control):
		return value
	var floor_value := maxf(deadzone, TRIGGER_DEADZONE if str((CONTROLS[control] as Array)[0]) == "trigger" else 0.0)
	return shaped(value, floor_value, curve)


## A stick as a 2D vector (x right, y up), with a round dead zone so walking
## diagonally is as easy as walking straight.
static func stick(left: bool) -> Vector2:
	var x := raw("Left stick X (right +)" if left else "Right stick X (right +)")
	var y := raw("Left stick Y (up +)" if left else "Right stick Y (up +)")
	var vector := Vector2(x, y)
	var size := vector.length()
	if size <= STICK_DEADZONE:
		return Vector2.ZERO
	var spread := minf((size - STICK_DEADZONE) / (1.0 - STICK_DEADZONE), 1.0)
	return vector / size * spread


## True while a pad button is held.
static func held(button: JoyButton) -> bool:
	if not fake.is_empty():
		for control in fake:
			var spec: Array = CONTROLS.get(control, [])
			if spec.size() > 1 and str(spec[0]) == "button" and int(spec[1]) == int(button):
				return float(fake[control]) != 0.0
	var pad := device()
	return pad >= 0 and Input.is_joy_button_pressed(pad, button)


## True if an input event is a pad button going down.
static func pressed_in(event: InputEvent, button: JoyButton) -> bool:
	var joy := event as InputEventJoypadButton
	return joy != null and joy.pressed and joy.button_index == button
