"""Generate src/voice.mach: the deathmatch announcer's lines, as samples.

The lines are spoken by eSpeak NG (https://github.com/espeak-ng/espeak-ng),
a formant synthesizer: speech from rules, not from recordings of anyone. Its
voice is then made an arena announcer's: slowed and so lowered, made to
ring, driven a little into distortion, put in a hall (the grander the line,
the more it rings and the bigger the hall), and written as the game's own
sound format, unsigned 8-bit at 11025 Hz. Run from the repository root, with
ESPEAK_NG naming espeak-ng's executable and, if it is not installed where it
expects, ESPEAK_DATA the folder that holds its espeak-ng-data:

    ESPEAK_NG=.../espeak-ng.exe ESPEAK_DATA=... python harness/genvoice.py [previews-dir]

With a directory, each line is also written there as a WAV, to listen to.
"""
import io
import os
import subprocess
import sys
import tempfile
import wave

import numpy as np

RATE = 11025

# the lines, in the order announce.mach numbers them, each with how grand it
# is, 0 to 9: the grander, the more its voice rings and the bigger the hall
# it is said in. The ladder of kills in quick succession climbs first, then
# the ladder of kills without dying; first blood stands with godlike, and
# rampage is the top of everything.
LINES = [
    ("first_blood", "First blood!", 8),
    ("double_kill", "Double kill!", 1),
    ("multi_kill", "Multi kill!", 2),
    ("ultra_kill", "Ultra kill!", 3),
    ("monster_kill", "Mon-ster kill!", 4),
    ("killing_spree", "Killing spree!", 5),
    ("rampage", "Rampage!", 9),
    ("dominating", "Dominating!", 6),
    ("unstoppable", "Unstoppable!", 7),
    ("godlike", "God like!", 8),
]
TOP = 9


def speak(text):
    """One line from eSpeak NG, as floats in -1..1 and its sample rate."""
    exe = os.environ.get("ESPEAK_NG", "espeak-ng")
    with tempfile.TemporaryDirectory() as tmp:
        out = os.path.join(tmp, "line.wav")
        cmd = [exe]
        if os.environ.get("ESPEAK_DATA"):
            cmd.append("--path=" + os.environ["ESPEAK_DATA"])
        # a low male voice, slow, with the words kept apart
        cmd += ["-v", "en-us+m3", "-p", "12", "-s", "125", "-g", "3", "-a", "200", "-w", out, text]
        subprocess.run(cmd, check=True)
        w = wave.open(out)
        assert w.getnchannels() == 1 and w.getsampwidth() == 2
        data = np.frombuffer(w.readframes(w.getnframes()), dtype="<i2").astype(np.float64) / 32768
        rate = w.getframerate()
        w.close()
        return data, rate


def peak(x, freq, gain_db, q):
    """A resonance: a band around freq lifted by gain_db, the narrower and
    longer-ringing for a higher q. The usual two-pole peaking filter."""
    amp = 10 ** (gain_db / 40)
    w = 2 * np.pi * freq / RATE
    alpha = np.sin(w) / (2 * q)
    b0, b1, b2 = 1 + alpha * amp, -2 * np.cos(w), 1 - alpha * amp
    a0, a1, a2 = 1 + alpha / amp, -2 * np.cos(w), 1 - alpha / amp
    b0, b1, b2, a1, a2 = b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0
    y = np.zeros(len(x))
    x1 = x2 = y1 = y2 = 0.0
    for n in range(len(x)):
        v = b0 * x[n] + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2, x1, y2, y1 = x1, x[n], y1, v
        y[n] = v
    return y


def hall(seconds):
    """What a clap sounds like in a hall that rings for so long: a few
    early reflections off the walls, then a wash dying away, duller as it
    goes. The same numbers every run."""
    n = int(RATE * seconds)
    t = np.arange(n) / RATE
    noise = np.random.RandomState(1993).uniform(-1, 1, n)
    # 60 dB down by the end
    wash = noise * np.exp(-6.9 * t / seconds)
    wash = np.convolve(wash, np.ones(3) / 3, mode="same")
    # the wash builds over the first 30 ms, after the walls answer
    wash *= np.minimum(1, t / 0.03)
    for delay, gain in ((0.023, 0.9), (0.041, -0.7), (0.067, 0.6), (0.097, -0.45)):
        wash[int(RATE * delay)] += gain * 4
    return wash / np.sqrt((wash ** 2).sum())


def announcer(data, rate, grand):
    """Lower, grittier, and in a hall; resampled to the game's rate.

    grand: 0 to TOP. It sets how hard the voice's chest and throat ring, how
    long the hall does, and how much of what is heard is the hall."""
    much = grand / TOP
    # played slower: longer and lower by the same factor
    slow = 0.82
    # resample to the game's rate through that slowing, by linear interpolation
    # after a moving-average low-pass to keep what the lower rate cannot hold
    step = rate * slow / RATE
    width = max(1, int(round(step)))
    kernel = np.ones(width) / width
    smooth = np.convolve(data, kernel, mode="same")
    at = np.arange(0, len(smooth) - 1, step)
    low = np.floor(at).astype(int)
    frac = at - low
    out = smooth[low] * (1 - frac) + smooth[low + 1] * frac

    # trim the silence either side
    loud = np.nonzero(np.abs(out) > 0.02)[0]
    out = out[max(0, loud[0] - 50):loud[-1] + 50]

    # resonance: the chest and the throat ring, harder and for longer
    out = np.concatenate([out, np.zeros(int(RATE * 0.15))])
    out = peak(out, 130, 3 + 11 * much, 1.2 + 3.8 * much)
    out = peak(out, 520, 1 + 7 * much, 1.5 + 4.5 * much)

    # driven: louder, then bent
    out = np.tanh(out / np.abs(out).max() * 2.6)

    # reverb: a hall ringing from 0.35 s up to 2.6 s, and from a sixth of what
    # is heard up to nearly as much as the voice
    seconds = 0.35 + 2.25 * much
    wet = np.convolve(out, hall(seconds))
    mix = 0.5 + 2.6 * much
    wet = wet * mix
    wet[:len(out)] += out
    # the last of it fades to nothing, and what is too quiet to hear goes
    wet = wet / np.abs(wet).max() * 0.95
    heard = np.nonzero(np.abs(wet) > 0.012)[0]
    wet = wet[:heard[-1] + 1]
    fade = min(len(wet), int(RATE * 0.2))
    wet[-fade:] *= np.linspace(1, 0, fade)
    return wet


def main():
    previews = sys.argv[1] if len(sys.argv) > 1 else None
    clips = []
    for name, text, grand in LINES:
        data, rate = speak(text)
        clip = announcer(data, rate, grand)
        samples = np.clip(np.rint(clip * 127 + 128), 0, 255).astype(np.uint8)
        clips.append(samples)
        if previews:
            os.makedirs(previews, exist_ok=True)
            w = wave.open(os.path.join(previews, name + ".wav"), "wb")
            w.setnchannels(1)
            w.setsampwidth(1)
            w.setframerate(RATE)
            w.writeframes(samples.tobytes())
            w.close()
        print("%-14s %5d samples, %.2f s" % (name, len(samples), len(samples) / RATE))

    starts, total = [], 0
    for c in clips:
        starts.append(total)
        total += len(c)
    everything = np.concatenate(clips)
    lines = []
    for i in range(0, total, 24):
        lines.append("    " + ", ".join(str(v) for v in everything[i:i + 24]) + ",")
    lines[-1] = lines[-1].rstrip(",")
    src = """# the announcer's lines: unsigned 8-bit samples at 11025 Hz, one after another
#
# Generated by harness/genvoice.py from eSpeak NG's synthetic speech, slowed,
# driven, and put in a hall that grows with the line. Do not edit.

pub val LINES: i32 = %d;

# where each line begins in SAMPLES, and how long it is
pub val START:  [%d]i32 = [%d]i32{%s};
pub val LENGTH: [%d]i32 = [%d]i32{%s};

pub val SAMPLES: [%d]u8 = [%d]u8{
%s
};
""" % (len(clips), len(clips), len(clips), ", ".join(map(str, starts)),
       len(clips), len(clips), ", ".join(str(len(c)) for c in clips),
       total, total, "\n".join(lines))
    io.open("src/voice.mach", "w", encoding="utf-8", newline="\n").write(src)
    print("src/voice.mach: %d samples in all, %.1f s" % (total, total / RATE))


main()
