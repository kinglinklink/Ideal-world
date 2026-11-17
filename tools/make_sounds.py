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


if __name__ == "__main__":
    main()
