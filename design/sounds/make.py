# Dewdrop's sounds: water, synthesised. usage: make.py <out dir>
import numpy as np, sys, os, wave
from scipy.signal import butter, sosfilt
SR = 48000
out = sys.argv[1]

def t(d): return np.arange(int(SR * d)) / SR
def env(n, a=0.002, d=0.2, curve=6.0):
    """attack then exponential decay over the rest"""
    x = np.linspace(0, 1, n)
    at = np.clip(x / max(a, 1e-4) * (n / SR), 0, 1) if a > 0 else np.ones(n)
    at = np.minimum(1, np.arange(n) / max(1, a * SR))
    return at * np.exp(-curve * x / max(d, 1e-3) * (n / SR))
def plip(f0, f1, d=0.12, amp=1.0, bright=0.3, curve=7.0):
    """a water drop: a tone whose pitch rises as the bubble shrinks"""
    tt = t(d)
    k = 1 - np.exp(-tt / (d * 0.25))
    f = f0 + (f1 - f0) * k
    ph = 2 * np.pi * np.cumsum(f) / SR
    y = np.sin(ph) + bright * np.sin(2 * ph + 0.5) * np.exp(-tt * 40)
    return y * np.exp(-curve * tt / d) * amp
def bubble(f, d=0.25, amp=1.0, wob=0.0):
    """a rounder, lower bloop"""
    tt = t(d)
    fr = f * (1 + 0.35 * (1 - np.exp(-tt / (d * 0.3)))) * (1 + wob * np.sin(2 * np.pi * 9 * tt))
    ph = 2 * np.pi * np.cumsum(fr) / SR
    y = np.sin(ph) + 0.15 * np.sin(3 * ph)
    return y * np.exp(-5 * tt / d) * amp
def bell(f, d=0.8, amp=1.0):
    """a small glass bell: a few inharmonic partials"""
    tt = t(d)
    y = np.zeros_like(tt)
    for r, a, dec in [(1, 1, 1), (2.76, 0.35, 1.6), (5.4, 0.15, 2.4), (1.005, 0.5, 1.1)]:
        y += a * np.sin(2 * np.pi * f * r * tt) * np.exp(-dec * 4 * tt / d)
    return y / 2 * amp
def swoosh(d=0.4, f0=400, f1=3000, amp=1.0, rise=True):
    """filtered noise sliding up (or down)"""
    n = int(SR * d); x = np.random.default_rng(3).standard_normal(n)
    pieces = []
    seg = 512
    for i in range(0, n, seg):
        k = i / n if rise else 1 - i / n
        fc = f0 * (f1 / f0) ** k
        sos = butter(2, [max(50, fc * 0.6), min(SR / 2 - 1, fc * 1.4)], btype='band', fs=SR, output='sos')
        pieces.append(sosfilt(sos, x[i:i + seg]))
    y = np.concatenate(pieces)
    e = np.sin(np.pi * np.linspace(0, 1, n)) ** 1.5
    return y / (np.abs(y).max() + 1e-9) * e * amp
def splash(d=0.5, amp=1.0):
    n = int(SR * d); x = np.random.default_rng(5).standard_normal(n)
    sos = butter(2, [900, 6000], btype='band', fs=SR, output='sos')
    y = sosfilt(sos, x) * np.exp(-7 * t(d))
    return y / (np.abs(y).max() + 1e-9) * amp
def place(parts, d):
    """mix (offset_s, signal) pairs into a buffer of d seconds"""
    y = np.zeros(int(SR * d))
    for off, sig in parts:
        i = int(off * SR); j = min(len(y), i + len(sig)); y[i:j] += sig[:j - i]
    return y
def glide(f0, f1, d, amp=1.0, shape='sine', vib=0.0):
    tt = t(d)
    f = f0 * (f1 / f0) ** (tt / d) * (1 + vib * np.sin(2 * np.pi * 6 * tt))
    ph = 2 * np.pi * np.cumsum(f) / SR
    y = np.sin(ph) + 0.2 * np.sin(2 * ph)
    e = np.sin(np.pi * np.clip(tt / d, 0, 1)) ** 0.7
    return y * e * amp

def finish_sound(y, peak, d=None):
    if d: y = place([(0, y)], d)
    n = len(y); fade = int(SR * 0.012)
    y[-fade:] *= np.linspace(1, 0, fade)
    y[:min(fade, n)] *= np.linspace(0, 1, min(fade, n))
    y = y / (np.abs(y).max() + 1e-9) * peak
    # stereo: a little width from a 0.4 ms offset
    off = int(SR * 0.0004)
    L = y; R = np.concatenate([np.zeros(off), y[:-off]]) if off < n else y
    s = np.stack([L, 0.5 * (R + y)], axis=1)
    return (np.clip(s, -1, 1) * 32767).astype('<i2')

def write(name, data):
    w = wave.open(os.path.join(out, name + '.wav'), 'wb'); w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR)
    w.writeframes(data.tobytes()); w.close()

C6, D6, E6, G6, A6, C7, E7, G7 = 1046.5, 1174.7, 1318.5, 1568.0, 1760.0, 2093.0, 2637.0, 3136.0
sounds = {
    # tiny ones
    'tick':    (place([(0, plip(1800, 2600, 0.06, curve=9))], 0.07), 0.03),
    'hover':   (place([(0, plip(1500, 2300, 0.08))], 0.08), 0.025),
    'blip':    (place([(0, plip(1100, 1900, 0.10))], 0.10), 0.05),
    'wink':    (place([(0, plip(1300, 2400, 0.14, bright=0.5))], 0.21), 0.06),
    'pop':     (place([(0, bubble(420, 0.22)), (0, splash(0.08, 0.25))], 0.35), 0.10),
    'work':    (place([(0, plip(700, 1100, 0.14)), (0.16, plip(900, 1400, 0.14))], 0.38), 0.10),
    'think':   (place([(0, bubble(380, 0.18, 0.8)), (0.2, bubble(430, 0.2, 0.8))], 0.44), 0.16),
    'search':  (place([(0, plip(900, 1500, 0.1)), (0.12, plip(1100, 1800, 0.1)), (0.24, plip(1350, 2200, 0.12))], 0.46), 0.15),
    'peek':    (place([(0, plip(800, 1300, 0.16)), (0.17, plip(1200, 2000, 0.2))], 0.45), 0.15),
    # the island
    'open':    (place([(0, swoosh(0.34, 300, 2500, 0.5)), (0.3, plip(1000, 1700, 0.18))], 0.5), 0.09),
    'close':   (place([(0, swoosh(0.3, 2200, 350, 0.5, rise=False)), (0.26, bubble(300, 0.16, 0.7))], 0.43), 0.08),
    'send':    (place([(0, swoosh(0.3, 500, 4000, 0.6)), (0.3, plip(1500, 2600, 0.15))], 0.48), 0.10),
    'attach':  (place([(0, glide(1800, 500, 0.4, 0.5)), (0.38, splash(0.4, 0.8)), (0.4, bubble(260, 0.3))], 0.9), 0.34),
    'gulp':    (place([(0, glide(900, 240, 0.35, 0.8)), (0.34, bubble(200, 0.35))], 0.75), 0.43),
    'slap':    (place([(0, splash(0.45)), (0, bubble(140, 0.2, 0.7))], 0.6), 0.21),
    # moods
    'greet':   (place([(0, plip(C6, C6 * 1.02, 0.3, 0.9, curve=4)), (0.14, plip(E6, E6 * 1.02, 0.3, 0.9, curve=4)), (0.28, bell(G6, 0.5, 0.9))], 0.75), 0.45),
    'proud':   (place([(0, bell(G6, 0.4)), (0.15, bell(C7, 0.4)), (0.3, bell(E7, 0.55, 1.1))], 0.86), 0.48),
    'finish':  (place([(0, bell(C6, 0.6)), (0.12, bell(E6, 0.6)), (0.24, bell(G6, 0.7)), (0.36, bell(C7, 0.8, 1.2)), (0.4, swoosh(0.6, 3000, 8000, 0.12))], 1.16), 0.6),
    'approve': (place([(0, plip(E6, E6 * 1.02, 0.25, curve=4)), (0.22, plip(A6, A6 * 1.02, 0.35, curve=3.5))], 0.6), 0.22),
    'approval':(place([(0, plip(A6, A6 * 1.02, 0.2, curve=4)), (0.18, plip(A6, A6 * 1.02, 0.2, curve=4)), (0.42, bell(E7, 0.45, 0.9))], 0.88), 0.5),
    'question':(place([(0, glide(500, 1200, 0.45, 0.9)), (0.48, plip(1400, 2200, 0.2))], 0.7), 0.3),
    'love':    (place([(0, bell(E6, 0.6, 0.8)), (0.18, bell(G6 * 1.0, 0.6, 0.8)), (0.3, swoosh(0.5, 2500, 7000, 0.1))], 0.79), 0.26),
    'error':   (place([(0, bubble(260, 0.3, 1, wob=0.08)), (0.28, bubble(200, 0.35, 1, wob=0.08)), (0.55, bubble(150, 0.3, 0.9))], 0.84), 0.5),
    'annoyed': (place([(0, bubble(330, 0.25, 1, wob=0.05)), (0.22, bubble(300, 0.3, 1, wob=0.05))], 0.59), 0.27),
    'dizzy':   (place([(0, glide(900, 300, 0.95, 0.9, vib=0.12)), (0.2, bubble(500, 0.2, 0.4)), (0.5, bubble(400, 0.2, 0.4)), (0.75, bubble(320, 0.2, 0.4))], 0.98), 0.27),
    'rate':    (place([(0, bubble(230, 0.3)), (0.33, bubble(190, 0.33))], 0.67), 0.24),
    'sleep':   (place([(0, glide(420, 260, 0.4, 0.7))], 0.45), 0.06),
    'yawn':    (place([(0, glide(300, 520, 0.3, 0.7)), (0.3, glide(520, 240, 0.42, 0.8))], 0.73), 0.11),
}
for name, (y, peak) in sounds.items():
    write(name, finish_sound(y, peak))
print(len(sounds), 'sounds')
