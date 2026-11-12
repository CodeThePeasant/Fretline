"""Generate an original plucked phrase for repeatable end-to-end testing."""
import json
import math
import struct
import wave
from pathlib import Path

root = Path(__file__).resolve().parents[1]
destination = root / "examples"
destination.mkdir(exist_ok=True)
sr = 44100
sequence = [64, 66, 67, 71, 69, 67, 66, 64, 67, 69, 71, 74, 71, 69, 67, 64]
samples = [0.] * int(sr * 0.3)
truth = []
for index, midi in enumerate(sequence):
    duration = 0.52 if index in (7, 15) else 0.30
    truth.append(dict(pitch=midi, start=len(samples) / sr, duration=duration))
    frequency = 440 * 2 ** ((midi - 69) / 12)
    for i in range(int(sr * duration)):
        t = i / sr
        attack = min(t / 0.006, 1)
        release = min((duration - t) / 0.025, 1)
        signal = sum(math.sin(2 * math.pi * frequency * h * t) / h**2 for h in range(1, 7))
        samples.append(0.55 * signal * attack * release * math.exp(-2.8 * t))
    samples.extend([0.] * int(sr * 0.055))
samples.extend([0.] * int(sr * 0.3))
with wave.open(str(destination / "demo-solo.wav"), "wb") as file:
    file.setnchannels(1); file.setsampwidth(2); file.setframerate(sr)
    file.writeframes(struct.pack(f"<{len(samples)}h", *(int(max(-1, min(1, s)) * 32767) for s in samples)))
(destination / "demo-ground-truth.json").write_text(json.dumps(truth, indent=2))
print(destination / "demo-solo.wav")
