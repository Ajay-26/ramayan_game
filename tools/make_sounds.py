"""
Synthesizes every sound effect, ambience loop and music track for the game
into assets/audio/*.wav (22 kHz mono, 16-bit). Pure Python, no dependencies.

    python3 tools/make_sounds.py

All sounds are made from scratch here (noise, oscillators, filters,
envelopes), so there are no third-party licenses to track. Loops (names
ending in _loop, and music_*) are built to repeat seamlessly; scripts/autoload/
sfx.gd turns looping on when it loads them. To swap in a recorded sound, drop
a .wav with the same name into assets/audio/.
"""

import math
import random
import struct
import wave
from pathlib import Path

RATE = 22050
OUT = Path(__file__).resolve().parent.parent / "assets" / "audio"
TAU = math.tau


# --- building blocks -----------------------------------------------------------

def n_samples(seconds):
    return int(seconds * RATE)


def silence(seconds):
    return [0.0] * n_samples(seconds)


def white(seconds, rng):
    return [rng.uniform(-1.0, 1.0) for _ in range(n_samples(seconds))]


def brown(seconds, rng):
    out, v = [], 0.0
    for _ in range(n_samples(seconds)):
        v = (v + rng.uniform(-1, 1) * 0.08) * 0.995
        out.append(v * 3.0)
    return out


def lowpass(x, cutoff):
    """One-pole lowpass. `cutoff` is Hz, or a function t -> Hz."""
    out, y = [], 0.0
    for i, s in enumerate(x):
        c = cutoff(i / RATE) if callable(cutoff) else cutoff
        a = 1.0 - math.exp(-TAU * max(c, 1.0) / RATE)
        y += a * (s - y)
        out.append(y)
    return out


def highpass(x, cutoff):
    low = lowpass(x, cutoff)
    return [a - b for a, b in zip(x, low)]


def bandpass(x, low_hz, high_hz):
    return lowpass(highpass(x, low_hz), high_hz)


def osc(seconds, freq, shape="sine", phase=0.0):
    """Oscillator; `freq` is Hz or a function t -> Hz."""
    out, p = [], phase
    for i in range(n_samples(seconds)):
        f = freq(i / RATE) if callable(freq) else freq
        p += f / RATE
        frac = p % 1.0
        if shape == "sine":
            v = math.sin(TAU * p)
        elif shape == "saw":
            v = 2.0 * frac - 1.0
        elif shape == "square":
            v = 1.0 if frac < 0.5 else -1.0
        else:  # triangle
            v = 4.0 * abs(frac - 0.5) - 1.0
        out.append(v)
    return out


def env(x, attack, decay_time, curve=4.0):
    """Quick attack, exponential decay over `decay_time` seconds."""
    out = []
    for i, s in enumerate(x):
        t = i / RATE
        a = min(t / attack, 1.0) if attack > 0 else 1.0
        d = math.exp(-curve * max(t - attack, 0.0) / decay_time)
        out.append(s * a * d)
    return out


def shape_env(x, points):
    """Piecewise-linear envelope: [(time, level), ...]."""
    out = []
    for i, s in enumerate(x):
        t = i / RATE
        level = points[-1][1]
        for (t0, l0), (t1, l1) in zip(points, points[1:]):
            if t0 <= t <= t1:
                level = l0 + (l1 - l0) * ((t - t0) / max(t1 - t0, 1e-6))
                break
        out.append(s * level)
    return out


def gain(x, g):
    return [s * g for s in x]


def drive(x, amount):
    return [math.tanh(s * amount) / math.tanh(amount) for s in x]


def mix(*tracks, length=None):
    n = length if length is not None else max(len(t) for t in tracks)
    out = [0.0] * n
    for t in tracks:
        for i in range(min(n, len(t))):
            out[i] += t[i]
    return out


def place(dest, src, at_seconds, g=1.0, wrap=False):
    start = int(at_seconds * RATE)
    n = len(dest)
    for i, s in enumerate(src):
        j = start + i
        if wrap:
            j %= n
        elif j >= n:
            break
        dest[j] += s * g


def pad(x, seconds):
    return x + silence(seconds)


def normalize(x, peak=0.9):
    m = max((abs(s) for s in x), default=0.0)
    return [s * peak / m for s in x] if m > 0 else x


def fade_out(x, seconds):
    n = min(n_samples(seconds), len(x))
    out = list(x)
    for i in range(n):
        out[len(x) - n + i] *= 1.0 - i / n
    return out


def make_loop(x, crossfade):
    """Fold the tail over the head so the sound repeats without a seam."""
    n = n_samples(crossfade)
    body = list(x[:-n])
    tail = x[-n:]
    for i in range(n):
        k = i / n
        body[i] = body[i] * k + tail[i] * (1.0 - k)
    return body


def karplus(seconds, freq, rng, damping=0.996):
    period = int(RATE / freq)
    buf = [rng.uniform(-1, 1) for _ in range(period)]
    out = []
    for i in range(n_samples(seconds)):
        v = buf[i % period]
        nxt = buf[(i + 1) % period]
        buf[i % period] = (v + nxt) * 0.5 * damping
        out.append(v)
    return out


def write(name, x, peak=0.9):
    OUT.mkdir(parents=True, exist_ok=True)
    data = normalize(x, peak)
    with wave.open(str(OUT / f"{name}.wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1.0, min(1.0, s)) * 32767)) for s in data))
    print(f"wrote assets/audio/{name}.wav ({len(data) / RATE:.2f}s)")


# --- sounds --------------------------------------------------------------------

def whoosh(rng, seconds, low, high, peak_at=0.4):
    noise = white(seconds, rng)
    sweep = lambda t: low + (high - low) * math.sin(math.pi * min(t / seconds, 1.0))
    body = lowpass(highpass(noise, 200), sweep)
    return shape_env(body, [(0, 0), (seconds * peak_at, 1), (seconds, 0)])


def thump(seconds, f0, f1, decay):
    return env(osc(seconds, lambda t: f1 + (f0 - f1) * math.exp(-t * 30)), 0.002, decay)


def metal(rng, seconds, base, partials=(1.0, 2.76, 5.4, 8.93), decay=0.25):
    tone = mix(*[gain(env(osc(seconds, base * p), 0.001, decay / (1 + k * 0.6)), 1.0 / (1 + k))
                 for k, p in enumerate(partials)])
    click = env(highpass(white(0.03, rng), 2000), 0.0005, 0.01)
    return mix(tone, gain(click, 0.8))


def growl(rng, seconds, f0, f1, rough=0.4, cutoff=900):
    vib = lambda t: (f0 + (f1 - f0) * t / seconds) * (1 + 0.04 * math.sin(TAU * 7 * t))
    voice = mix(osc(seconds, vib, "saw"), gain(osc(seconds, lambda t: vib(t) * 0.5, "square"), 0.5))
    breath = gain(bandpass(white(seconds, rng), 300, 2000), rough)
    return drive(lowpass(mix(voice, breath), cutoff), 2.0)


def crackle(rng, seconds, density=60, length=None):
    out = silence(seconds)
    for _ in range(int(density * seconds)):
        at = rng.uniform(0, seconds - 0.01)
        pop = env(highpass(white(0.015, rng), 1500), 0.0005, 0.006)
        place(out, pop, at, rng.uniform(0.2, 1.0), wrap=True)
    return out


def build_all():
    rng = random.Random(7)

    # Rama's melee and weapons
    write("punch_swing", whoosh(rng, 0.18, 600, 2500), 0.5)
    write("sword_swing", mix(whoosh(rng, 0.28, 900, 5000, 0.5), gain(metal(rng, 0.28, 2400, decay=0.3), 0.08)), 0.6)
    write("punch", mix(thump(0.18, 160, 55, 0.12), gain(lowpass(env(white(0.1, rng), 0.001, 0.05), 1800), 0.6)), 0.85)
    write("sword_hit", mix(metal(rng, 0.45, 1250, decay=0.35), gain(thump(0.2, 140, 60, 0.1), 0.6),
                           gain(env(bandpass(white(0.12, rng), 800, 5000), 0.001, 0.05), 0.5)), 0.85)
    write("slam", mix(thump(0.9, 110, 32, 0.6), gain(lowpass(env(white(0.9, rng), 0.002, 0.5), 600), 0.7),
                      gain(metal(rng, 0.4, 700, decay=0.3), 0.25)), 0.95)
    write("bow_release", mix(gain(karplus(0.5, 98, rng, 0.993), 0.9), gain(whoosh(rng, 0.25, 1500, 6000, 0.15), 0.4)), 0.7)
    write("bow_charged", mix(gain(karplus(0.7, 73, rng, 0.995), 1.0), gain(whoosh(rng, 0.35, 1200, 7000, 0.12), 0.6),
                             gain(env(osc(0.5, lambda t: 900 + 2500 * t), 0.01, 0.3), 0.15)), 0.8)
    write("arrow_hit", mix(thump(0.15, 260, 90, 0.07), gain(env(bandpass(white(0.08, rng), 600, 3500), 0.0005, 0.03), 0.7)), 0.75)
    write("arrow_thunk", mix(thump(0.12, 400, 180, 0.05), gain(env(highpass(white(0.05, rng), 1200), 0.0005, 0.02), 0.5)), 0.5)
    whir = [s * (0.6 + 0.4 * math.sin(TAU * 28 * i / RATE)) for i, s in enumerate(bandpass(white(0.7, rng), 600, 3500))]
    write("chakra", shape_env(mix(whir, gain(osc(0.7, lambda t: 520 + 300 * math.sin(TAU * 3 * t)), 0.25)),
                              [(0, 0), (0.08, 1), (0.5, 0.7), (0.7, 0)]), 0.55)
    write("dodge", whoosh(rng, 0.3, 300, 1800, 0.3), 0.5)
    write("land", mix(thump(0.2, 120, 50, 0.1), gain(lowpass(env(white(0.15, rng), 0.001, 0.06), 900), 0.6)), 0.5)
    write("hurt", mix(growl(rng, 0.28, 190, 120, 0.6, 1400), gain(thump(0.15, 140, 60, 0.08), 0.7)), 0.7)
    shimmer = mix(*[gain(env(osc(1.6, 440 * r), 0.3 + k * 0.08, 1.2), 0.3) for k, r in enumerate((1, 1.5, 2, 3, 4))])
    write("astra", mix(shimmer, gain(pad(silence(0.5), 0) + thump(1.2, 90, 30, 0.9), 0.9),
                       gain(pad(silence(0.5), 0) + lowpass(env(white(1.0, rng), 0.005, 0.6), 2500), 0.6)), 0.95)
    heal = silence(1.2)
    for k, f in enumerate((660, 880, 1320)):
        place(heal, env(osc(1.0, f), 0.005, 0.7), k * 0.08, 0.4)
    write("heal", heal, 0.55)

    # Enemies and props
    write("enemy_hit", mix(thump(0.16, 130, 60, 0.08), gain(lowpass(env(white(0.1, rng), 0.001, 0.04), 2200), 0.7)), 0.7)
    ash = mix(gain(crackle(rng, 0.9, 120), 0.6), gain(whoosh(rng, 0.9, 200, 1400, 0.15), 0.8),
              gain(env(growl(rng, 0.6, 140, 70, 0.5, 700), 0.01, 0.4), 0.5))
    write("ash", ash, 0.7)
    write("growl", shape_env(growl(rng, 0.7, 95, 80, 0.5, 900), [(0, 0), (0.08, 1), (0.5, 0.8), (0.7, 0)]), 0.6)
    write("explosion", mix(gain(lowpass(env(brown(1.6, rng), 0.003, 1.0), 900), 1.0), thump(1.2, 90, 28, 0.7),
                           gain(crackle(rng, 1.2, 50), 0.4)), 0.95)
    bell = mix(*[gain(env(osc(2.4, 520 * p), 0.002, 2.0 / (1 + k * 0.4)), a)
                 for k, (p, a) in enumerate(((1, 1), (2.0, 0.6), (2.4, 0.5), (3.0, 0.35), (4.5, 0.25), (5.9, 0.15)))])
    write("bell", bell, 0.7)
    grind = lowpass(mix(brown(1.4, rng), gain(crackle(rng, 1.4, 80), 0.3)), 700)
    write("gate", shape_env(mix(grind, gain(thump(1.4, 60, 40, 1.0), 0.4)), [(0, 0), (0.1, 1), (1.1, 0.8), (1.4, 0)]), 0.7)
    write("pickup", mix(*[gain(env(osc(1.4, f), 0.005, 1.0), 0.3) for f in (523, 659, 784, 1046)]), 0.6)

    # Tataka
    roar = mix(growl(rng, 2.2, 75, 55, 0.7, 1100), gain(growl(rng, 2.2, 38, 30, 0.5, 400), 0.8),
               gain(bandpass(white(2.2, rng), 400, 3000), 0.3))
    write("roar", shape_env(roar, [(0, 0), (0.25, 1), (1.4, 0.9), (2.2, 0)]), 0.95)
    write("swoop", mix(whoosh(rng, 1.3, 200, 2200, 0.5), gain(whoosh(rng, 1.3, 80, 500, 0.5), 0.8)), 0.8)
    whistle = env(osc(1.1, lambda t: 1800 - 1300 * t), 0.2, 0.9, 1.0)
    write("dive_warn", mix(gain(whistle, 0.4), gain(whoosh(rng, 1.1, 300, 2500, 0.85), 0.8)), 0.7)
    write("stone_fall", mix(gain(env(osc(1.3, lambda t: 1400 - 900 * t), 0.3, 1.0, 1.0), 0.25),
                            gain(whoosh(rng, 1.3, 200, 1500, 0.9), 0.7)), 0.5)
    fire = mix(lowpass(white(0.8, rng), lambda t: 400 + 2400 * t), gain(crackle(rng, 0.8, 80), 0.4))
    write("fire_whoosh", shape_env(fire, [(0, 0), (0.1, 1), (0.8, 0)]), 0.7)

    # Weather and ambience
    crack = env(highpass(white(0.25, rng), 1500), 0.001, 0.08)
    rumble = lowpass(env(brown(4.0, rng), 0.05, 3.0, 3.0), lambda t: 500 - 80 * t)
    write("thunder", mix(gain(crack, 0.9), gain(rumble, 1.0), gain(pad(silence(0.15), 0) + lowpass(env(brown(1.0, rng), 0.01, 0.7), 1200), 0.6)), 0.95)
    rain = bandpass(white(6.5, rng), 900, 6000)
    rain = mix(gain(rain, 0.6), gain(crackle(rng, 6.5, 260), 0.25))
    write("rain_loop", make_loop(rain, 0.5), 0.5)
    wind = brown(8.5, rng)
    wind = [s * (0.6 + 0.4 * math.sin(TAU * i / RATE / 8.0)) for i, s in enumerate(lowpass(wind, lambda t: 300 + 250 * math.sin(TAU * t / 4.0)))]
    write("wind_loop", make_loop(wind, 0.5), 0.5)
    fire_loop = mix(gain(lowpass(brown(4.5, rng), 500), 0.7), gain(crackle(rng, 4.5, 50), 0.5))
    write("fire_loop", make_loop(fire_loop, 0.5), 0.55)
    write("ui_click", mix(env(osc(0.06, 1200), 0.001, 0.02), gain(env(highpass(white(0.03, rng), 3000), 0.0005, 0.008), 0.4)), 0.4)

    # Music
    write("music_calm", drone(rng, 16.0, 110.0, drums=False), 0.6)
    write("music_battle", drone(rng, 9.6, 98.0, drums=True, bpm=100, intensity=0.8), 0.75)
    write("music_boss", drone(rng, 8.0, 92.5, drums=True, bpm=120, intensity=1.0), 0.8)


def drone(rng, seconds, root, drums=False, bpm=100, intensity=1.0):
    """A tanpura-like drone on the root and fifth (sa and pa), with dhol-style
    drums on top for battle. Built on a ring buffer so it loops seamlessly."""
    out = silence(seconds)
    n = len(out)
    for k, (ratio, amp) in enumerate(((0.5, 0.6), (1.0, 0.5), (1.5, 0.35), (2.0, 0.2), (3.0, 0.08))):
        # Whole numbers of cycles per loop, so the drone itself loops cleanly.
        f = round(root * ratio * seconds) / seconds
        beat = 0.15 * (k + 1) / seconds * round(seconds)
        for i in range(n):
            t = i / RATE
            out[i] += amp * math.sin(TAU * f * t) * (0.75 + 0.25 * math.sin(TAU * beat * t / 4.0 + k))
    # Shimmer of the strings being plucked, every two beats.
    pluck_every = 60.0 / 50.0
    t = 0.0
    while t < seconds:
        place(out, gain(karplus(1.6, root, rng, 0.997), 0.35), t, 1.0, wrap=True)
        place(out, gain(karplus(1.6, root * 1.5, rng, 0.997), 0.25), t + pluck_every * 0.5, 1.0, wrap=True)
        t += pluck_every
    if drums:
        beat = 60.0 / bpm
        steps = int(round(seconds / beat * 2))
        # Dhol pattern in eighth notes: low "dha", high "na", rests.
        pattern = "D.nD.n.nD.nDn.n." if intensity < 1.0 else "D.nDDn.nD.nDnnDn"
        for s in range(steps):
            at = s * beat / 2.0
            hit = pattern[s % len(pattern)]
            if hit == "D":
                place(out, gain(thump(0.5, 130, 48, 0.35), 1.6 * intensity), at, wrap=True)
            elif hit == "n":
                tone = mix(env(osc(0.18, 340), 0.001, 0.08), gain(env(bandpass(white(0.1, rng), 1500, 6000), 0.0005, 0.03), 0.6))
                place(out, gain(tone, 0.7 * intensity), at, wrap=True)
    return out


if __name__ == "__main__":
    build_all()
