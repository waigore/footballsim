import numpy as np, wave, os

sr = 44100
rng = np.random.default_rng(7)
os.makedirs("audio", exist_ok=True)


def write_wav(path, data, stereo=False):
    d = np.clip(data, -1, 1)
    if stereo:
        if d.ndim == 1:
            d = np.stack([d, d], axis=1)
        raw = (d * 32767).astype('<i2').tobytes()
        ch = 2
    else:
        raw = (d * 32767).astype('<i2').tobytes()
        ch = 1
    with wave.open(path, 'wb') as w:
        w.setnchannels(ch)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(raw)


def pink(n, seed):
    r = np.random.default_rng(seed)
    out = np.zeros(n)
    for octave in range(1, 7):
        step = 2 ** octave
        k = max(2, int(np.ceil(n / step)))
        vals = r.normal(0, 1, k)
        out += np.repeat(vals, step)[:n] / (octave ** 0.7)
    return out / np.max(np.abs(out))


# crowd loop
dur = 24.0
n = int(sr * dur)
t = np.arange(n) / sr
b = pink(n, 11)
mod = 0.55 + 0.18 * np.sin(2 * np.pi * 0.08 * t) + 0.10 * np.sin(2 * np.pi * 0.13 * t + 1.2) + 0.05 * np.sin(2 * np.pi * 0.31 * t)
mod = np.clip(mod, 0.2, 1.0)
left = b * mod
right = np.roll(b, int(sr * 0.013)) * mod
xf = int(sr * 1.5)
ramp = np.linspace(0, 1, xf)
left[:xf] = left[:xf] * ramp + left[-xf:] * (1 - ramp)
right[:xf] = right[:xf] * ramp + right[-xf:] * (1 - ramp)
left = left[:-xf] * 0.9
right = right[:-xf] * 0.9
write_wav("audio/crowd_loop.wav", np.stack([left, right], axis=1), True)

# whistle
dur = 0.9
n = int(sr * dur)
t = np.arange(n) / sr
f = 2900 + 130 * np.sin(2 * np.pi * 7 * t)
ph = 2 * np.pi * np.cumsum(f) / sr
tone = np.sin(ph) + 0.35 * np.sin(2 * ph) + 0.15 * np.sin(3 * ph)
env = np.minimum(1, t / 0.02) * np.exp(-t * 3.2)
write_wav("audio/whistle.wav", tone * env * 0.34, False)

# kick
dur = 0.22
n = int(sr * dur)
t = np.arange(n) / sr
th = np.sin(2 * np.pi * (95 - 40 * t / dur) * t) * np.exp(-t * 30)
click = rng.normal(0, 1, n) * np.exp(-t * 190) * 0.5
write_wav("audio/kick.wav", th * 0.55 + click * 0.5, False)

# goal roar
dur = 5.0
n = int(sr * dur)
t = np.arange(n) / sr
b = pink(n, 23)
env = np.minimum(1, t / 0.25) * (0.55 + 0.45 * np.exp(-((t - 1.1) / 1.4) ** 2))
env *= np.exp(-np.maximum(0, t - 2.8) * 0.9)
write_wav("audio/goal_roar.wav", b * env, True)

# near-miss ooh
dur = 2.2
n = int(sr * dur)
t = np.arange(n) / sr
b = pink(n, 31)
env = np.minimum(1, t / 0.12) * np.exp(-np.maximum(0, t - 0.5) * 1.4)
write_wav("audio/ooh.wav", b * env, True)

print("audio done", [(f, os.path.getsize('audio/' + f)) for f in os.listdir('audio')])
