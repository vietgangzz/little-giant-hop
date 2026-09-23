#!/usr/bin/env python3
"""Synthesises every sound in the game from scratch (stdlib only).

    python3 tools/synth.py [out_dir]

Writes 16-bit WAVs; tools/build_sounds.sh converts them to CAF for the app.
The music loop is rendered with wrap-around indexing, so delay tails and
releases that run past the end land back at the start: the loop is seamless.
"""
import math
import os
import random
import struct
import sys
import wave
from array import array

SR = 44100
TAU = 2 * math.pi
random.seed(7)


def midi(n):
    return 440.0 * 2 ** ((n - 69) / 12)


# ---------------------------------------------------------------- oscillators

def osc(kind, phase, duty=0.5):
    p = phase % 1.0
    if kind == "sine":
        return math.sin(TAU * p)
    if kind == "tri":
        return 4 * abs(p - 0.5) - 1
    if kind == "saw":
        return 2 * p - 1
    if kind == "square":
        return 1.0 if p < duty else -1.0
    raise ValueError(kind)


def adsr(t, dur, a, d, s, r):
    """Envelope for a note held `dur` seconds, releasing over `r`."""
    if t < a:
        return t / a if a > 0 else 1.0
    if t < a + d:
        return 1 - (1 - s) * (t - a) / d
    if t < dur:
        return s
    if t < dur + r:
        return s * (1 - (t - dur) / r)
    return 0.0


class Track:
    """Stereo float buffer. `wrap=True` folds writes past the end to the start."""

    def __init__(self, seconds, wrap=False):
        self.n = int(seconds * SR)
        self.l = array("f", bytes(4 * self.n))
        self.r = array("f", bytes(4 * self.n))
        self.wrap = wrap


def pan_gains(pan):
    ang = (pan + 1) * math.pi / 4
    return math.cos(ang) * 1.414, math.sin(ang) * 1.414


def note(track, start, dur, freq, kind="sine", amp=0.3, env=(0.005, 0.05, 0.7, 0.08),
         duty=0.5, pan=0.0, vib=0.0, vib_rate=5.5, cutoff=None, glide_from=None,
         glide_time=0.03):
    """Render one note. `freq` may be a float or a function of time."""
    a, d, s, r = env
    total = dur + r
    i0 = int(start * SR)
    gl, gr = pan_gains(pan)
    phase = random.random() if kind != "sine" else 0.0
    lp = 0.0
    alpha = None
    if cutoff:
        alpha = 1 - math.exp(-TAU * cutoff / SR)
    for k in range(int(total * SR)):
        t = k / SR
        f = freq(t) if callable(freq) else freq
        if glide_from and t < glide_time:
            f = glide_from + (f - glide_from) * (t / glide_time)
        if vib:
            f *= 1 + vib * math.sin(TAU * vib_rate * t) * min(1.0, t / 0.15)
        phase += f / SR
        v = osc(kind, phase, duty) * adsr(t, dur, a, d, s, r) * amp
        if alpha is not None:
            lp += alpha * (v - lp)
            v = lp
        idx = i0 + k
        if track.wrap:
            idx %= track.n
        elif idx >= track.n:
            break
        track.l[idx] += v * gl
        track.r[idx] += v * gr


def noise_burst(track, start, dur, amp, decay, hp=0.0, lp=None, pan=0.0):
    i0 = int(start * SR)
    gl, gr = pan_gains(pan)
    prev_in = prev_hp = lp_state = 0.0
    a_lp = 1 - math.exp(-TAU * lp / SR) if lp else None
    for k in range(int(dur * SR)):
        t = k / SR
        x = random.uniform(-1, 1)
        if hp:
            y = hp * (prev_hp + x - prev_in)
            prev_in, prev_hp = x, y
            x = y
        if a_lp:
            lp_state += a_lp * (x - lp_state)
            x = lp_state
        v = x * amp * math.exp(-t / decay)
        idx = i0 + k
        if track.wrap:
            idx %= track.n
        elif idx >= track.n:
            break
        track.l[idx] += v * gl
        track.r[idx] += v * gr


def kick(track, start, amp=0.9):
    i0 = int(start * SR)
    phase = 0.0
    for k in range(int(0.32 * SR)):
        t = k / SR
        f = 45 + 110 * math.exp(-t / 0.035)
        phase += f / SR
        v = math.sin(TAU * phase) * math.exp(-t / 0.13) * amp
        if t < 0.004:  # click
            v += random.uniform(-1, 1) * 0.25 * amp
        idx = (i0 + k) % track.n if track.wrap else i0 + k
        if idx < track.n:
            track.l[idx] += v
            track.r[idx] += v


def snare(track, start, amp=0.45):
    note(track, start, 0.02, 190, "tri", amp * 0.7, (0.001, 0.08, 0.0, 0.01))
    noise_burst(track, start, 0.22, amp, 0.055, hp=0.7)


def hat(track, start, amp=0.12, open_=False, pan=0.25):
    noise_burst(track, start, 0.25 if open_ else 0.05, amp, 0.09 if open_ else 0.014,
                hp=0.97, pan=pan)


# ---------------------------------------------------------------- effects

def one_pole_lp(buf, cutoff):
    a = 1 - math.exp(-TAU * cutoff / SR)
    y = 0.0
    for i in range(len(buf)):
        y += a * (buf[i] - y)
        buf[i] = y


def ping_pong(track, src, delay_s, feedback, mix):
    """Adds a ping-pong echo of `src` (a Track) into `track`, with wrap."""
    n = track.n
    dl = int(delay_s * SR)
    tap_l = array("f", src.l)
    tap_r = array("f", src.r)
    gain = mix
    for rep in range(6):
        off = dl * (rep + 1)
        tl, tr = (tap_r, tap_l) if rep % 2 == 0 else (tap_l, tap_r)
        for i in range(n):
            j = (i + off) % n
            track.l[j] += tl[i] * gain
            track.r[j] += tr[i] * gain
        gain *= feedback


def mix_into(dst, src, gain=1.0):
    for i in range(dst.n):
        dst.l[i] += src.l[i] * gain
        dst.r[i] += src.r[i] * gain


def master(track, peak=0.89, drive=1.4):
    for buf in (track.l, track.r):
        for i in range(len(buf)):
            buf[i] = math.tanh(buf[i] * drive)
    m = max(max(abs(x) for x in track.l), max(abs(x) for x in track.r)) or 1
    g = peak / m
    for buf in (track.l, track.r):
        for i in range(len(buf)):
            buf[i] *= g


def fade_edges(track, fade_in=0.002, fade_out=0.02):
    fi, fo = int(fade_in * SR), int(fade_out * SR)
    for buf in (track.l, track.r):
        for i in range(min(fi, len(buf))):
            buf[i] *= i / fi
        for i in range(min(fo, len(buf))):
            buf[-1 - i] *= i / fo


def write(track, path, stereo=True):
    with wave.open(path, "wb") as w:
        w.setnchannels(2 if stereo else 1)
        w.setsampwidth(2)
        w.setframerate(SR)
        frames = bytearray()
        for i in range(track.n):
            l = max(-1.0, min(1.0, track.l[i]))
            if stereo:
                r = max(-1.0, min(1.0, track.r[i]))
                frames += struct.pack("<hh", int(l * 32767), int(r * 32767))
            else:
                m = max(-1.0, min(1.0, (track.l[i] + track.r[i]) * 0.5))
                frames += struct.pack("<h", int(m * 32767))
        w.writeframes(bytes(frames))
    print("wrote", path)


# ---------------------------------------------------------------- SFX

def sfx_hop():
    t = Track(0.22)
    note(t, 0, 0.07, lambda x: 260 * 2 ** (min(x, 0.06) / 0.06 * 1.35), "sine", 0.8,
         (0.002, 0.05, 0.4, 0.09))
    note(t, 0, 0.05, lambda x: 520 * 2 ** (min(x, 0.05) / 0.05 * 1.2), "tri", 0.25,
         (0.002, 0.04, 0.2, 0.05))
    noise_burst(t, 0, 0.06, 0.18, 0.015, hp=0.9)
    master(t, 0.8, 1.2)
    fade_edges(t)
    return t


def sfx_score():
    t = Track(0.7)
    for start, f, amp in ((0.0, midi(88), 0.5), (0.075, midi(95), 0.55)):
        for ratio, pamp, dec in ((1, 1, 0.22), (2.76, 0.25, 0.06), (5.4, 0.08, 0.03)):
            note(t, start, 0.001, f * ratio, "sine", amp * pamp, (0.001, dec, 0.0, dec * 2))
        note(t, start, 0.001, f, "sine", amp * 0.6, (0.002, 0.001, 1.0, 0.45))
    master(t, 0.75, 1.0)
    fade_edges(t)
    return t


def sfx_spark():
    t = Track(0.75)
    for i, n in enumerate((84, 88, 91, 96, 100)):
        s = i * 0.045
        note(t, s, 0.03, midi(n), "tri", 0.35, (0.001, 0.04, 0.3, 0.2), pan=(i - 2) * 0.3)
        note(t, s, 0.001, midi(n) * 2, "sine", 0.12, (0.001, 0.02, 0.0, 0.15))
    noise_burst(t, 0.0, 0.5, 0.05, 0.12, hp=0.985)
    master(t, 0.7, 1.0)
    fade_edges(t)
    return t


def sfx_hit():
    t = Track(0.6)
    kick(t, 0, 1.0)
    noise_burst(t, 0, 0.3, 0.9, 0.06, lp=2400)
    note(t, 0, 0.05, 95, "square", 0.35, (0.001, 0.05, 0.3, 0.05), cutoff=1800)
    note(t, 0.0, 0.12, lambda x: 900 * 2 ** (-x / 0.05), "saw", 0.25, (0.001, 0.1, 0.0, 0.02),
         cutoff=3000)
    master(t, 0.95, 2.2)
    fade_edges(t)
    return t


def sfx_fall():
    t = Track(0.95)
    note(t, 0, 0.7, lambda x: 1000 * 2 ** (-x / 0.28), "tri", 0.5, (0.01, 0.1, 0.8, 0.15),
         vib=0.03, vib_rate=11)
    master(t, 0.6, 1.0)
    fade_edges(t)
    return t


def sfx_milestone():
    t = Track(1.5)
    seq = (69, 73, 76, 81, 85, 88)
    for i, n in enumerate(seq):
        note(t, i * 0.06, 0.05, midi(n), "square", 0.18, (0.002, 0.04, 0.5, 0.1), duty=0.25,
             pan=-0.3 + i * 0.12, cutoff=5000)
    for n in (81, 85, 88, 93):
        note(t, 0.38, 0.4, midi(n), "saw", 0.12, (0.005, 0.15, 0.6, 0.5), cutoff=3500,
             vib=0.006)
    for s in (0.38, 0.5):
        note(t, s, 0.001, midi(100), "sine", 0.2, (0.001, 0.001, 1.0, 0.4))
    kick(t, 0.38, 0.5)
    noise_burst(t, 0.38, 0.9, 0.12, 0.25, hp=0.98)
    master(t, 0.8, 1.3)
    fade_edges(t)
    return t


def sfx_gameover():
    t = Track(2.0)
    seq = ((0.0, 0.18, 76), (0.2, 0.18, 75), (0.4, 0.18, 74), (0.62, 0.8, 73))
    for s, d, n in seq:
        note(t, s, d, midi(n), "square", 0.2, (0.005, 0.05, 0.7, 0.2), duty=0.3, cutoff=2200,
             vib=0.018 if d > 0.5 else 0.0, vib_rate=6)
        note(t, s, d, midi(n - 12), "tri", 0.25, (0.005, 0.05, 0.7, 0.2))
    master(t, 0.7, 1.1)
    fade_edges(t)
    return t


def sfx_swoosh():
    t = Track(0.35)
    i0 = 0
    lp = bp = 0.0
    for k in range(int(0.3 * SR)):
        x = k / (0.3 * SR)
        fc = 400 + 5000 * math.sin(math.pi * x) ** 2
        f = 2 * math.sin(math.pi * fc / SR)
        q = 0.35
        inp = random.uniform(-1, 1)
        hp = inp - lp - q * bp
        bp += f * hp
        lp += f * bp
        v = bp * 0.5 * math.sin(math.pi * x)
        t.l[i0 + k] += v * (1.2 - x)
        t.r[i0 + k] += v * (0.2 + x)
    master(t, 0.55, 1.0)
    fade_edges(t)
    return t


def sfx_tap():
    t = Track(0.12)
    note(t, 0, 0.02, 1320, "sine", 0.5, (0.001, 0.02, 0.2, 0.05))
    note(t, 0.03, 0.02, 1760, "sine", 0.4, (0.001, 0.02, 0.2, 0.05))
    master(t, 0.5, 1.0)
    fade_edges(t)
    return t


# ---------------------------------------------------------------- music

BPM = 112
BEAT = 60 / BPM
BAR = BEAT * 4
BARS = 16

CHORDS = {  # A minor: i - VI - III - VII
    "Am": (57, 60, 64),
    "F": (53, 57, 60),
    "C": (48, 52, 55),
    "G": (55, 59, 62),
}
PROG = ["Am", "F", "C", "G"] * 4

MELODY = {  # bar index -> (beat, beats, midi)
    8: ((0, 1, 76), (1, .5, 74), (1.5, .5, 72), (2, 1.5, 69), (3.5, .5, 72)),
    9: ((0, 1.5, 77), (1.5, .5, 76), (2, 2, 72)),
    10: ((0, 1, 76), (1, .5, 79), (1.5, .5, 76), (2, 1, 74), (3, 1, 72)),
    11: ((0, 2, 74), (2, 1, 71), (3, 1, 74)),
    12: ((0, 1, 76), (1, .5, 74), (1.5, .5, 72), (2, 1, 69), (3, 1, 81)),
    13: ((0, 1.5, 81), (1.5, .5, 79), (2, 2, 77)),
    14: ((0, 1, 79), (1, 1, 76), (2, 1, 72), (3, 1, 76)),
    15: ((0, 3, 74), (3, 1, 71)),
}


def music():
    length = BAR * BARS
    drums = Track(length, wrap=True)
    synths = Track(length, wrap=True)
    arp = Track(length, wrap=True)

    kicks = []
    for bar in range(BARS):
        b0 = bar * BAR
        for beat in range(4):
            s = b0 + beat * BEAT
            kick(drums, s, 0.85)
            kicks.append(s)
            if beat in (1, 3):
                snare(drums, s, 0.42)
            hat(drums, s + BEAT / 2, 0.13, open_=(beat == 3 and bar % 2 == 1), pan=0.3)
            hat(drums, s + BEAT * 0.75, 0.05, pan=-0.25)
        if bar == BARS - 1:  # fill into the loop point
            for k in range(4):
                snare(drums, b0 + 3 * BEAT + k * BEAT / 4, 0.18 + k * 0.06)

    for bar, name in enumerate(PROG):
        b0 = bar * BAR
        root = CHORDS[name][0]
        while root > 45:
            root -= 12
        # bass: driving eighths with an octave hop
        pattern = (0, 0, 12, 0, 0, 12, 0, 7)
        for i, off in enumerate(pattern):
            note(synths, b0 + i * BEAT / 2, BEAT / 2 * 0.8, midi(root + off), "saw", 0.22,
                 (0.003, 0.08, 0.55, 0.04), cutoff=620)
            note(synths, b0 + i * BEAT / 2, BEAT / 2 * 0.8, midi(root + off - 12), "sine", 0.28,
                 (0.003, 0.05, 0.8, 0.04))
        # pad: detuned saws, wide stereo, slow swell
        for n in CHORDS[name]:
            for det, pan in ((-0.004, -0.7), (0.004, 0.7)):
                note(synths, b0, BAR * 0.95, midi(n + 12) * (1 + det), "saw", 0.045,
                     (0.35, 0.4, 0.8, 0.5), pan=pan, cutoff=1500)
        # arp: sixteenths over two octaves
        tones = [n + 24 for n in CHORDS[name]] + [CHORDS[name][0] + 36]
        order = (0, 1, 2, 3, 2, 1, 0, 1, 2, 3, 2, 1, 0, 2, 3, 1)
        for i, idx in enumerate(order):
            accent = 1.0 if i % 4 == 0 else 0.7
            note(arp, b0 + i * BEAT / 4, BEAT / 4 * 0.55, midi(tones[idx]), "square",
                 0.07 * accent, (0.002, 0.05, 0.35, 0.05), duty=0.3, cutoff=3800,
                 pan=0.35 if i % 2 else -0.35)

    for bar, phrase in MELODY.items():
        prev = None
        for beat, beats, n in phrase:
            s = bar * BAR + beat * BEAT
            f = midi(n)
            note(synths, s, beats * BEAT * 0.92, f, "square", 0.12, (0.01, 0.1, 0.75, 0.12),
                 duty=0.22, cutoff=3000, vib=0.007, vib_rate=5.2,
                 glide_from=prev, glide_time=0.035)
            note(synths, s, beats * BEAT * 0.92, f * 1.003, "saw", 0.05, (0.01, 0.1, 0.7, 0.12),
                 cutoff=2400, pan=0.4)
            prev = f

    ping_pong(arp, arp, BEAT * 0.75, 0.45, 0.35)

    # sidechain pump on everything tonal
    duck = array("f", [1.0]) * synths.n
    for s in kicks:
        i0 = int(s * SR)
        for k in range(int(0.3 * SR)):
            g = 1 - 0.5 * math.exp(-k / SR / 0.09)
            j = (i0 + k) % synths.n
            duck[j] = min(duck[j], g)
    for tr in (synths, arp):
        for i in range(tr.n):
            tr.l[i] *= duck[i]
            tr.r[i] *= duck[i]

    out = Track(length, wrap=True)
    mix_into(out, drums, 0.9)
    mix_into(out, synths, 1.0)
    mix_into(out, arp, 1.0)
    master(out, 0.85, 1.25)
    return out


def main():
    out_dir = sys.argv[1] if len(sys.argv) > 1 else "build/sounds"
    os.makedirs(out_dir, exist_ok=True)
    only = set(sys.argv[2:])
    jobs = {
        "hop": (sfx_hop, True), "score": (sfx_score, True), "spark": (sfx_spark, True),
        "hit": (sfx_hit, True), "fall": (sfx_fall, True), "milestone": (sfx_milestone, True),
        "gameover": (sfx_gameover, True), "swoosh": (sfx_swoosh, True), "tap": (sfx_tap, True),
        "music": (music, True),
    }
    for name, (fn, stereo) in jobs.items():
        if only and name not in only:
            continue
        write(fn(), os.path.join(out_dir, name + ".wav"), stereo)


if __name__ == "__main__":
    main()
