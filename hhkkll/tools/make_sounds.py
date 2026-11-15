#!/usr/bin/env python3
"""Synthesises every HHKKLL sound effect from scratch (no third-party audio,
no licensing issues). Output: 44.1 kHz mono 16-bit WAV in app/assets/sounds.

    python3 tools/make_sounds.py
"""
import math, os, random, struct, wave

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "app", "assets", "sounds")
random.seed(7)


def silence(d):
    return [0.0] * int(SR * d)


def env_adsr(n, a=0.01, d=0.1, s=0.7, r=0.2):
    out = []
    A, D, R = int(a * SR), int(d * SR), int(r * SR)
    S = max(0, n - A - D - R)
    for i in range(n):
        if i < A:
            v = i / max(1, A)
        elif i < A + D:
            v = 1 - (1 - s) * (i - A) / max(1, D)
        elif i < A + D + S:
            v = s
        else:
            v = s * max(0.0, 1 - (i - A - D - S) / max(1, R))
        out.append(v)
    return out


def tone(freq, d, kind="sine", vol=0.5, a=0.005, dcy=0.08, s=0.6, r=0.15, f_end=None, vib=0.0):
    n = int(SR * d)
    e = env_adsr(n, a, dcy, s, r)
    out, ph = [], 0.0
    for i in range(n):
        f = freq if f_end is None else freq * (f_end / freq) ** (i / n)
        if vib:
            f *= 1 + vib * math.sin(2 * math.pi * 5.5 * i / SR)
        ph += 2 * math.pi * f / SR
        if kind == "sine":
            v = math.sin(ph)
        elif kind == "square":
            v = 0.6 * (1 if math.sin(ph) >= 0 else -1) + 0.4 * math.sin(ph)
        elif kind == "saw":
            v = 2 * ((ph / (2 * math.pi)) % 1) - 1
        elif kind == "tri":
            v = 2 * abs(2 * ((ph / (2 * math.pi)) % 1) - 1) - 1
        else:
            v = math.sin(ph)
        out.append(v * e[i] * vol)
    return out


def noise(d, vol=0.3, lp=0.1, a=0.01, dcy=0.1, s=0.5, r=0.3, sweep=None):
    n = int(SR * d)
    e = env_adsr(n, a, dcy, s, r)
    out, y = [], 0.0
    for i in range(n):
        k = lp if sweep is None else sweep[0] + (sweep[1] - sweep[0]) * (i / n)
        y += k * (random.uniform(-1, 1) - y)
        out.append(y * e[i] * vol * (1 / max(0.15, k ** 0.5)) * 0.4)
    return out


def mix(*tracks, at=None):
    at = at or [0] * len(tracks)
    n = max(int(o * SR) + len(t) for t, o in zip(tracks, at))
    out = [0.0] * n
    for t, o in zip(tracks, at):
        off = int(o * SR)
        for i, v in enumerate(t):
            out[off + i] += v
    return out


def reverb(x, wet=0.25, delays=(0.031, 0.047, 0.071, 0.097, 0.13), fb=0.45):
    out = list(x) + [0.0] * int(SR * 1.2)
    for d in delays:
        D = int(d * SR)
        g = wet
        for rep in range(6):
            off = D * (rep + 1)
            for i, v in enumerate(x):
                if i + off < len(out):
                    out[i + off] += v * g
            g *= fb
    return out


def norm(x, peak=0.89):
    m = max(1e-9, max(abs(v) for v in x))
    return [v * peak / m for v in x]


def fade_tail(x, ms=40):
    n = int(SR * ms / 1000)
    for i in range(min(n, len(x))):
        x[-1 - i] *= i / n
    return x


def save(name, x):
    x = fade_tail(norm(x))
    os.makedirs(OUT, exist_ok=True)
    with wave.open(os.path.join(OUT, name + ".wav"), "w") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, v)) * 32767)) for v in x))


def boom(d=2.6, f0=70, f1=28, vol=1.0):
    return mix(tone(f0, d, "sine", vol, 0.002, 0.3, 0.4, d * 0.7, f_end=f1),
               noise(d * 0.6, vol * 0.5, 0.02, 0.002, 0.2, 0.3, d * 0.4))


def chord(freqs, d, kind="saw", vol=0.18, **kw):
    return mix(*[tone(f, d, kind, vol, **kw) for f in freqs])


# --- cinematic intro -------------------------------------------------------
save("intro_boom", reverb(boom(3.0, 62, 24), 0.3))
save("intro_whoosh", reverb(noise(1.6, 0.9, 0.0, 0.9, 0.2, 0.6, 0.5, sweep=(0.01, 0.35)), 0.2))
save("intro_hit", reverb(mix(boom(2.2, 90, 30, 0.9),
                             chord([220, 330, 440, 660], 2.0, "saw", 0.08, a=0.003, dcy=0.4, s=0.3, r=1.4),
                             tone(1760, 1.5, "sine", 0.06, 0.001, 0.6, 0.2, 0.8, vib=0.004)), 0.35))
save("intro_rise", reverb(mix(noise(2.0, 0.6, 0.0, 1.6, 0.1, 0.9, 0.3, sweep=(0.005, 0.25)),
                              tone(110, 2.0, "saw", 0.12, 1.5, 0.1, 0.9, 0.4, f_end=220)), 0.25))

# --- game events -----------------------------------------------------------
save("start", reverb(mix(*[tone(f, 0.35, "saw", 0.22, dcy=0.1, s=0.5, r=0.2) for f in (392, 523, 659, 784)],
                         chord([523, 659, 784, 1046], 1.2, "saw", 0.12, a=0.01, dcy=0.3, s=0.5, r=0.7),
                         boom(1.2, 80, 40, 0.5),
                         at=[0, 0.12, 0.24, 0.36, 0.5, 0.5]), 0.25))
save("question", reverb(mix(noise(0.5, 0.5, 0.0, 0.3, 0.1, 0.5, 0.15, sweep=(0.02, 0.4)),
                            tone(880, 0.6, "sine", 0.35, 0.002, 0.2, 0.3, 0.35),
                            tone(1320, 0.6, "sine", 0.2, 0.002, 0.2, 0.3, 0.35), at=[0, 0.3, 0.3]), 0.3))
save("tick", tone(1200, 0.07, "square", 0.4, 0.001, 0.03, 0.2, 0.03))
save("tick_last", tone(1600, 0.12, "square", 0.45, 0.001, 0.05, 0.3, 0.05))
save("go", reverb(chord([880, 1108, 1318], 0.5, "square", 0.25, a=0.002, dcy=0.15, s=0.5, r=0.25), 0.2))
save("buzzer", mix(chord([523, 659, 784], 0.55, "square", 0.3, a=0.001, dcy=0.05, s=0.85, r=0.12),
                   noise(0.08, 0.5, 0.5, 0.001, 0.03, 0.2, 0.04)))
save("correct", reverb(mix(tone(784, 0.25, "tri", 0.5, dcy=0.08, s=0.5, r=0.12),
                           tone(1046, 0.5, "tri", 0.5, dcy=0.12, s=0.5, r=0.3),
                           tone(1568, 0.5, "sine", 0.2, dcy=0.12, s=0.4, r=0.3), at=[0, 0.12, 0.12]), 0.3))
save("wrong", mix(tone(196, 0.55, "square", 0.4, 0.002, 0.05, 0.8, 0.15, f_end=150),
                  tone(207, 0.55, "square", 0.3, 0.002, 0.05, 0.8, 0.15, f_end=155)))
save("strike", reverb(mix(boom(0.6, 120, 50, 0.9), noise(0.25, 0.7, 0.4, 0.001, 0.05, 0.3, 0.15),
                          tone(311, 0.4, "saw", 0.25, 0.001, 0.1, 0.4, 0.2, f_end=233)), 0.2))
save("eliminated", reverb(mix(tone(440, 1.3, "saw", 0.3, 0.005, 0.2, 0.7, 0.6, f_end=110),
                              tone(445, 1.3, "saw", 0.25, 0.005, 0.2, 0.7, 0.6, f_end=108),
                              boom(1.6, 70, 30, 0.9), at=[0, 0, 0.9]), 0.35))
knock = mix(noise(0.09, 0.9, 0.6, 0.0005, 0.03, 0.2, 0.05), tone(180, 0.12, "sine", 0.7, 0.0005, 0.05, 0.2, 0.06, f_end=120))
save("auction_win", reverb(mix(knock, knock, knock,
                               chord([659, 830, 987, 1318], 1.0, "tri", 0.18, a=0.005, dcy=0.3, s=0.4, r=0.6),
                               at=[0, 0.22, 0.44, 0.62]), 0.25))
save("bid", tone(990, 0.09, "tri", 0.5, 0.001, 0.04, 0.3, 0.04, f_end=1320))
save("reveal", reverb(mix(*[tone(f, 0.4, "sine", 0.25, 0.002, 0.15, 0.3, 0.2) for f in (1318, 1568, 1975)],
                          at=[0, 0.05, 0.1]), 0.35))
save("pass", tone(660, 0.18, "tri", 0.45, 0.002, 0.05, 0.4, 0.1, f_end=440))
fan = []
for j, (fs, t) in enumerate([((523, 659, 784), 0), ((587, 740, 880), 0.35), ((659, 830, 987), 0.7), ((784, 987, 1175, 1568), 1.05)]):
    fan.append((chord(fs, 0.5 if j < 3 else 2.4, "saw", 0.14, a=0.01, dcy=0.2, s=0.7, r=0.3 if j < 3 else 1.6), t))
save("winner", reverb(mix(*[f for f, _ in fan], boom(1.5, 90, 40, 0.6), noise(2.6, 0.25, 0.25, 0.4, 0.4, 0.6, 1.4),
                          at=[t for _, t in fan] + [1.05, 1.05]), 0.35))
print("sounds written to", os.path.abspath(OUT))
