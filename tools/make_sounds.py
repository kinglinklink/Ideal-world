"""Makes the game's sound effects from scratch, so nothing has to be
downloaded and every sound is free to share.

    python tools/make_sounds.py

Writes sounds/*.wav (mono, 16-bit, 22,050 Hz). Loops are made periodic, so
they repeat without a click: their tones are whole numbers of cycles long
and their noise is shaped in the frequency domain (which wraps round). Each
loop also carries a 'smpl' chunk marking the loop, which Godot's importer
reads.
"""

import os
import struct

import numpy as np

RATE = 22050
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "sounds")
rng = np.random.default_rng(7)


def seconds(n):
    return int(round(n * RATE))


def times(length):
    return np.arange(seconds(length)) / RATE


def shaped_noise(length, shape):
    """Noise of `length` seconds whose spectrum follows shape(freq in Hz).
    Made in the frequency domain, so it loops seamlessly."""
    count = seconds(length)
    spectrum = np.fft.rfft(rng.standard_normal(count))
    freq = np.fft.rfftfreq(count, 1.0 / RATE)
    spectrum *= shape(np.maximum(freq, 1.0))
    sound = np.fft.irfft(spectrum, count)
    return sound / (np.max(np.abs(sound)) + 1e-9)


def band(low, high, slope=1.0):
    """A smooth band-pass shape from `low` to `high` Hz."""
    def shape(f):
        return (1.0 / (1.0 + (low / f) ** (2 * slope))) * (1.0 / (1.0 + (f / high) ** (2 * slope)))
    return shape


def lowpass(signal, cutoff):
    """A one-pole low-pass (not periodic: for one-shots)."""
    a = np.exp(-2.0 * np.pi * cutoff / RATE)
    out = np.empty_like(signal)
    y = 0.0
    for i, x in enumerate(signal):
        y = (1 - a) * x + a * y
        out[i] = y
    return out


def normalise(sound, peak=0.9):
    return sound * (peak / (np.max(np.abs(sound)) + 1e-9))


def write(name, sound, loop=False, peak=0.9):
    sound = normalise(np.asarray(sound, dtype=np.float64), peak)
    if not loop:
        # A short fade at both ends, so there is no click.
        fade = min(64, len(sound) // 4)
        sound[:fade] *= np.linspace(0, 1, fade)
        sound[-fade:] *= np.linspace(1, 0, fade)
    data = (np.clip(sound, -1, 1) * 32767).astype("<i2").tobytes()
    chunks = b"fmt " + struct.pack("<IHHIIHH", 16, 1, 1, RATE, RATE * 2, 2, 16)
    chunks += b"data" + struct.pack("<I", len(data)) + data
    if len(data) % 2:
        chunks += b"\x00"
    if loop:
        frames = len(sound)
        smpl = struct.pack("<9I", 0, 0, int(1e9 / RATE), 60, 0, 0, 0, 1, 0)
        smpl += struct.pack("<6I", 0, 0, 0, frames - 1, 0, 0)
        chunks += b"smpl" + struct.pack("<I", len(smpl)) + smpl
    with open(os.path.join(OUT, name + ".wav"), "wb") as f:
        f.write(b"RIFF" + struct.pack("<I", 4 + len(chunks)) + b"WAVE" + chunks)
    print("  %-16s %5.2f s%s" % (name, len(sound) / RATE, "  loop" if loop else ""))


def tone(t, freq, phase=0.0):
    return np.sin(2 * np.pi * freq * t + phase)


def envelope(t, attack, decay):
    return np.minimum(t / max(attack, 1e-6), 1.0) * np.exp(-np.maximum(t - attack, 0.0) / decay)


def main():
    os.makedirs(OUT, exist_ok=True)
    print("Writing sounds to", os.path.normpath(OUT))

    # --- Loops (lengths in whole seconds so every whole-Hz tone wraps) ---

    # An electric motor's whine and hum. Played faster or slower with its speed.
    t = times(1.0)
    motor = (tone(t, 220) + 0.5 * tone(t, 440) + 0.3 * tone(t, 660) + 0.15 * tone(t, 1320)
             + 0.25 * tone(t, 50) + 0.35 * shaped_noise(1.0, band(150, 2500)))
    write("motor_loop", motor, loop=True)

    # A jet: a broad roar with a turbine whine on top.
    t = times(2.0)
    roar = shaped_noise(2.0, lambda f: band(80, 1800, 0.7)(f) / np.sqrt(f / 100.0))
    whine = 0.12 * tone(t, 2400) + 0.08 * tone(t, 3600) + 0.06 * tone(t, 1200)
    write("jet_loop", roar + whine, loop=True)

    # A rocket or thruster: a rough, deep roar with crackle.
    rumble = shaped_noise(2.0, lambda f: band(30, 900, 0.8)(f) / (f / 60.0) ** 0.6)
    crackle = np.zeros(seconds(2.0))
    for at in rng.integers(0, len(crackle), 260):
        size = rng.uniform(0.3, 1.0)
        length = rng.integers(20, 90)
        end = min(at + length, len(crackle))
        crackle[at:end] += size * rng.standard_normal(end - at) * np.exp(-np.arange(end - at) / 25.0)
    write("rocket_loop", rumble + 0.15 * crackle, loop=True)

    # A thruster: a smooth, breathy rush with a low hum under it, no crackle.
    t = times(2.0)
    rush = shaped_noise(2.0, lambda f: band(120, 2200, 0.7)(f) / (f / 150.0) ** 0.5)
    write("thruster_loop", rush + 0.15 * tone(t, 70) + 0.08 * tone(t, 140), loop=True, peak=0.7)

    # A propeller: a buzz at the blade-passing rate (40 Hz here), rich in harmonics.
    t = times(1.0)
    blades = sum(tone(t, 40 * k) / k ** 0.9 for k in range(1, 30))
    chop = 0.5 + 0.5 * np.maximum(tone(t, 40), 0.0) ** 3
    write("prop_loop", blades * 0.5 + chop * shaped_noise(1.0, band(200, 3000)) * 0.8, loop=True)

    # Wind rushing past: a breathy band of noise that swells and falls.
    t = times(4.0)
    swell = 0.75 + 0.25 * tone(t, 0.5) * tone(t, 0.25, 1.0)
    write("wind_loop", shaped_noise(4.0, band(180, 1600, 0.6)) * swell, loop=True)

    # Daytime: a soft breeze and birds now and then.
    t = times(10.0)
    day = 0.25 * shaped_noise(10.0, band(150, 900, 0.6)) * (0.8 + 0.2 * tone(t, 0.3))
    for start in rng.uniform(0.2, 9.4, 9):
        notes = rng.integers(2, 6)
        base = rng.uniform(2600, 4200)
        for n in range(notes):
            begin = seconds(start + n * 0.11)
            length = seconds(rng.uniform(0.05, 0.09))
            if begin + length >= len(day):
                break
            lt = np.arange(length) / RATE
            sweep = base * (1 + 0.25 * np.sin(np.pi * lt / lt[-1])) * rng.uniform(0.9, 1.15)
            phase = 2 * np.pi * np.cumsum(sweep) / RATE
            day[begin:begin + length] += 0.35 * np.sin(phase) * np.sin(np.pi * lt / lt[-1])
    write("day_loop", day, loop=True, peak=0.7)

    # Night: crickets, a few chirps a second, over a low hush.
    t = times(8.0)
    night = 0.12 * shaped_noise(8.0, band(100, 600, 0.6))
    for cricket in range(3):
        carrier = rng.uniform(4000, 4800)
        rate = rng.uniform(1.6, 2.6)
        offset = rng.uniform(0, 1)
        chirp_phase = (t * rate + offset) % 1.0
        pulses = ((chirp_phase < 0.12) * (np.sin(2 * np.pi * t * 55) > 0)).astype(float)
        pulses = np.convolve(pulses, np.ones(40) / 40, mode="same")
        night += 0.25 * pulses * tone(t, round(carrier))
    write("night_loop", night, loop=True, peak=0.6)

    # --- One-shots ---

    # Machine gun: a sharp crack and a short thump.
    t = times(0.25)
    crack = rng.standard_normal(len(t)) * envelope(t, 0.0005, 0.018)
    thump = tone(t, 110) * envelope(t, 0.001, 0.05)
    write("gunshot", lowpass(crack, 6000) + 0.8 * thump)

    # Cannon: a deep boom falling in pitch, and a blast of noise.
    t = times(1.4)
    sweep = 2 * np.pi * np.cumsum(70 * np.exp(-t / 0.4) + 35) / RATE
    boom = np.sin(sweep) * envelope(t, 0.003, 0.35)
    blast = lowpass(rng.standard_normal(len(t)), 1200) * envelope(t, 0.001, 0.12)
    write("cannon", boom + 1.5 * blast)

    # Explosion: a burst, then a long rolling rumble.
    t = times(3.2)
    burst = lowpass(rng.standard_normal(len(t)), 2500) * envelope(t, 0.002, 0.15)
    rumble = lowpass(rng.standard_normal(len(t)), 220) * envelope(t, 0.02, 0.9)
    low = np.sin(2 * np.pi * np.cumsum(45 * np.exp(-t / 1.2) + 25) / RATE) * envelope(t, 0.005, 0.7)
    write("explosion", burst * 0.8 + rumble * 3.0 + low * 0.6)

    # Something big coming down: a long crumbling rumble with cracks in it.
    t = times(4.5)
    crumble = lowpass(rng.standard_normal(len(t)), 300) * envelope(t, 0.3, 1.6)
    cracks = np.zeros(len(t))
    for at in rng.integers(0, seconds(2.5), 40):
        length = seconds(0.05)
        cracks[at:at + length] += rng.standard_normal(length) * np.exp(-np.arange(length) / 120.0)
    write("collapse", crumble * 3.0 + lowpass(cracks, 3000) * 0.6)

    # One firing of a combustion cylinder: a low pop.
    t = times(0.12)
    pop = (tone(t, 85) * envelope(t, 0.001, 0.03)
           + 0.6 * lowpass(rng.standard_normal(len(t)), 1500) * envelope(t, 0.0005, 0.012))
    write("piston_pop", pop)

    # Interface: a soft tick, and two block knocks for placing and removing parts.
    # A keyboard key: a low, blocky thock with a short dull tick on top.
    t = times(0.07)
    thock = tone(t, 190) * envelope(t, 0.001, 0.012) + 0.5 * tone(t, 410) * envelope(t, 0.0005, 0.006)
    tick = lowpass(rng.standard_normal(len(t)), 2200) * envelope(t, 0.0003, 0.004)
    write("click", thock + 0.9 * tick, peak=0.5)
    t = times(0.12)
    write("place", (tone(t, 820) + 0.4 * tone(t, 1640)) * envelope(t, 0.001, 0.025)
          + 0.3 * rng.standard_normal(len(t)) * envelope(t, 0.0005, 0.006), peak=0.6)
    write("remove", (tone(t, 420) + 0.4 * tone(t, 630)) * envelope(t, 0.001, 0.03)
          + 0.3 * rng.standard_normal(len(t)) * envelope(t, 0.0005, 0.006), peak=0.6)

    # Spawn: a rising whoosh.
    t = times(0.6)
    rising = shaped_noise(0.6, band(300, 3000)) * envelope(t, 0.35, 0.12)
    write("spawn", rising, peak=0.6)

    # A splash, for hitting the water hard.
    t = times(1.0)
    splash = lowpass(rng.standard_normal(len(t)), 3500) * envelope(t, 0.01, 0.25)
    write("splash", splash + 0.3 * lowpass(rng.standard_normal(len(t)), 600) * envelope(t, 0.05, 0.4))


    # --- Weather, disasters, traffic and racing (made last, so the sounds
    # above keep the same random noise they always had) ---

    # Rain: a dense hiss of drops with a soft patter in it.
    t = times(6.0)
    rain = shaped_noise(6.0, band(400, 6000, 0.5))
    patter = np.zeros(len(t))
    for at in rng.integers(0, len(t) - 200, 2400):
        length = rng.integers(30, 120)
        patter[at:at + length] += rng.uniform(0.2, 1.0) * rng.standard_normal(length) * np.exp(-np.arange(length) / 20.0)
    write("rain_loop", rain * 0.7 + lowpass(patter, 4000) * 0.5, loop=True, peak=0.6)

    # A tornado: a deep, churning roar, like a freight train, that swells.
    t = times(6.0)
    roar = shaped_noise(6.0, lambda f: band(25, 700, 0.7)(f) / (f / 40.0) ** 0.7)
    churn = 0.7 + 0.3 * tone(t, 0.5) * tone(t, 1.0 / 3.0, 0.7)
    howl = shaped_noise(6.0, band(300, 900, 2.0)) * (0.5 + 0.5 * tone(t, 1.0 / 6.0))
    write("tornado_loop", roar * churn + 0.3 * howl, loop=True)

    # Engine sounds for traffic: a car's hum and a light plane's drone.
    t = times(1.0)
    car = sum(tone(t, 30 * k) / k for k in range(1, 18)) * 0.4 + 0.3 * shaped_noise(1.0, band(80, 900))
    write("car_loop", car, loop=True, peak=0.6)
    t = times(1.0)
    plane = sum(tone(t, 60 * k) / k ** 0.8 for k in range(1, 24)) * 0.4 + 0.4 * shaped_noise(1.0, band(150, 2500))
    write("plane_loop", plane * (0.8 + 0.2 * np.maximum(tone(t, 60), 0)), loop=True, peak=0.6)


    # Thunder: a sharp crack that rolls away into a long rumble.
    t = times(5.0)
    crack = lowpass(rng.standard_normal(len(t)), 3500) * envelope(t, 0.005, 0.12)
    roll = lowpass(rng.standard_normal(len(t)), 160) * envelope(t, 0.2, 1.6) * (0.7 + 0.3 * tone(t, 1.3))
    write("thunder", crack * 0.6 + roll * 3.5)

    # The ground shaking: a long, low rumble that grows and dies away.
    t = times(7.0)
    shake = lowpass(rng.standard_normal(len(t)), 90) * envelope(t, 2.0, 2.5)
    write("rumble", shake + 0.4 * tone(t, 28) * envelope(t, 2.0, 2.5))

    # A volcano erupting: an enormous boom and a roar that goes on.
    t = times(6.0)
    blast = lowpass(rng.standard_normal(len(t)), 1800) * envelope(t, 0.003, 0.3)
    boom = np.sin(2 * np.pi * np.cumsum(40 * np.exp(-t / 0.8) + 18) / RATE) * envelope(t, 0.005, 1.5)
    roar = lowpass(rng.standard_normal(len(t)), 400) * envelope(t, 0.4, 3.0)
    write("eruption", blast * 0.8 + boom * 1.2 + roar * 2.5)

    # A wall of water arriving: a rushing roar.
    t = times(4.0)
    rush = shaped_noise(4.0, lambda f: band(60, 2500, 0.6)(f) / (f / 100.0) ** 0.4) * envelope(t, 0.8, 1.8)
    write("wave_crash", rush)

    # Racing: the countdown beeps, the start, passing a ring, and money.
    t = times(0.25)
    write("beep", tone(t, 880) * envelope(t, 0.002, 0.08), peak=0.6)
    t = times(0.6)
    write("go", (tone(t, 1320) + 0.5 * tone(t, 1760)) * envelope(t, 0.002, 0.25), peak=0.7)
    t = times(0.5)
    write("checkpoint", (tone(t, 1046) * envelope(t, 0.002, 0.1)
                         + tone(t, 1568) * envelope(np.maximum(t - 0.08, 0), 0.002, 0.15) * (t > 0.08)), peak=0.6)
    t = times(0.9)
    coins = np.zeros(len(t))
    for n, at in enumerate([0.0, 0.07, 0.14, 0.24]):
        lt = np.maximum(t - at, 0)
        coins += (tone(t, 2093 + 300 * n) + 0.5 * tone(t, 3136 + 300 * n)) * envelope(lt, 0.001, 0.12) * (t >= at)
    write("cash", coins, peak=0.6)

    # --- Build 27: fire, damage, the camera, boats and birds ---
    # Added at the end, so the random numbers above (and so every older
    # sound) come out exactly as before.
    # Fire: a roaring bed with random crackles, looped.
    t = times(3.0)
    bed = shaped_noise(3.0, band(80, 900, 0.7))
    pops = np.zeros(len(t))
    for _ in range(70):
        at = rng.integers(0, len(t) - 400)
        width = int(rng.integers(40, 300))
        pops[at:at + width] += rng.standard_normal(width) * np.exp(-np.arange(width) / (width / 4.0)) * rng.uniform(0.3, 1.0)
    write("fire_loop", bed * 0.6 + lowpass(pops, 5000) * 0.9, loop=True, peak=0.7)
    # Fire catching: a whoosh.
    t = times(1.2)
    whoosh = shaped_noise(1.2, band(120, 2500, 0.8)) * envelope(t, 0.15, 0.6)
    write("fire_whoosh", whoosh, peak=0.8)
    # A damaged engine coughing.
    t = times(1.1)
    sputter = np.zeros(len(t))
    for n, at in enumerate([0.0, 0.13, 0.22, 0.45, 0.52, 0.78]):
        lt = np.maximum(t - at, 0)
        sputter += (rng.standard_normal(len(t)) * 0.6 + tone(t, 55 + 10 * n)) * envelope(lt, 0.004, 0.05) * (t >= at)
    write("sputter", lowpass(sputter, 1800), peak=0.8)
    # A bullet sparking off metal.
    t = times(0.25)
    ping = (tone(t, 3100) + 0.6 * tone(t, 4700) + 0.4 * tone(t, 6900)) * envelope(t, 0.0005, 0.04)
    write("spark", ping + 0.5 * rng.standard_normal(len(t)) * envelope(t, 0.0005, 0.01), peak=0.5)
    # The camera's shutter: two quick clicks.
    t = times(0.18)
    shutter = np.zeros(len(t))
    for at in [0.0, 0.07]:
        lt = np.maximum(t - at, 0)
        shutter += rng.standard_normal(len(t)) * envelope(lt, 0.0003, 0.008) * (t >= at)
    write("shutter", lowpass(shutter, 7000), peak=0.6)
    # An outboard motor, looped.
    t = times(2.0)
    put = np.maximum(tone(t, 32), 0) ** 3
    boat = put * shaped_noise(2.0, band(90, 1400)) + 0.3 * tone(t, 96) + 0.15 * tone(t, 192)
    write("boat_loop", boat, loop=True, peak=0.6)
    # A small bird's chirp.
    t = times(0.35)
    sweep = np.sin(2 * np.pi * np.cumsum(3800 + 1600 * np.sin(t * 60)) / RATE)
    chirp = sweep * envelope(t, 0.005, 0.05) * (t < 0.12) + sweep * envelope(np.maximum(t - 0.18, 0), 0.005, 0.05) * (t >= 0.18)
    write("chirp", chirp, peak=0.4)

if __name__ == "__main__":
    main()
