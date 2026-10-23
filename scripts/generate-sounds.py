#!/usr/bin/env python3
"""Original procedural reaction sounds for Whack. No sampled or third-party audio.
Re-run to reproduce the bundled mono 44.1 kHz PCM WAV assets.
"""
import math
from pathlib import Path
import struct
import wave

RATE = 44100
DESTINATION = Path(__file__).resolve().parents[1] / "Sources/WhackCore/Sounds"
DESTINATION.mkdir(parents=True, exist_ok=True)


def render(name, duration, synth):
    samples = [synth(i / RATE, duration) for i in range(round(duration * RATE))]
    peak = max(abs(v) for v in samples) or 1
    # Fade both ends to avoid clicks, and leave headroom.
    pcm = b"".join(struct.pack("<h", round(v / peak * 24000 * min(1, i / 220, (len(samples) - 1 - i) / 440)))
                   for i, v in enumerate(samples))
    with wave.open(str(DESTINATION / f"{name}.wav"), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(RATE)
        output.writeframes(pcm)


tau = math.tau
render("boing", .72, lambda t, d: math.sin(tau * (110*t + 85*(1-math.exp(-9*t))/9)
                                           + 3*math.sin(tau*19*t)*math.exp(-6*t)) * math.exp(-5*t))
render("squeak", .55, lambda t, d: (math.sin(tau*(750*t + 420*t*t - 600*t*t*t))
                                    + .25*math.sin(tau*2300*t)) * math.sin(math.pi*t/d)**1.3)


def trombone(t, duration):
    note = min(3, int(t / .26))
    frequency = [233.08, 220, 207.65, 174.61][note]
    local = t - note*.26
    envelope = min(1, local/.025) * min(1, (duration-t)/.12)
    return envelope * sum(math.sin(tau*frequency*t*n) / n**1.5 for n in range(1, 7))


def moan(t, duration):
    # A cartoon vowel: harmonic source with moving formant weights and breathy modulation.
    phase = tau * (145*t + 23*duration/math.pi*(1-math.cos(math.pi*t/duration)))
    fundamental = 145 + 23*math.sin(math.pi*t/duration)
    vowel = 0
    for harmonic in range(1, 18):
        frequency = fundamental * harmonic
        weight = .18/harmonic + math.exp(-((frequency-620)/200)**2)
        weight += .35*math.exp(-((frequency-1100)/240)**2)
        vowel += weight * math.sin(harmonic*phase + .035*math.sin(tau*5*t))
    return vowel * math.sin(math.pi*t/duration)**1.6 * (1 + .08*math.sin(tau*31*t))


render("sad-trombone", 1.15, trombone)
render("moan", 1.1, moan)
