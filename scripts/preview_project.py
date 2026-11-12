"""Render the actual TAB positions and inspect coverage against its source audio.

This is an evaluation utility, not a reference-transcription accuracy benchmark.
Run with engine/.venv/bin/python scripts/preview_project.py PROJECT.guitartab OUTPUT
Plotting additionally requires matplotlib in that environment.
"""
from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path

import numpy as np
import soundfile as sf

TUNING = [64, 59, 55, 50, 45, 40]
NAMES = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]


def name(pitch: int) -> str:
    return f"{NAMES[pitch % 12]}{pitch // 12 - 1}"


def render(notes: list[dict], seconds: float, sr: int) -> np.ndarray:
    result = np.zeros(round(seconds * sr), dtype=np.float64)
    for note in notes:
        # Read fret + string, independently of the stored MIDI field.
        pitch = TUNING[note["string"] - 1] + note["fret"]
        if pitch != note["pitch"]:
            raise ValueError(f"Pitch/position mismatch in {note['id']}")
        start = round(note["start"] * sr)
        end = min(len(result), round((note["start"] + note["duration"]) * sr))
        t = np.arange(end - start) / sr
        f0 = 440 * 2 ** ((pitch - 69) / 12)
        # Deterministic plucked timbre. No original samples are used in the TAB sound.
        tone = sum(np.sin(2 * np.pi * f0 * harmonic * t)
                   * np.exp(-(2.5 + harmonic * 0.65) * t) / harmonic**1.6
                   for harmonic in range(1, min(10, int(sr / 2 / f0))))
        attack = np.minimum(t / 0.004, 1)
        release = np.minimum((len(t) - 1 - np.arange(len(t))) / (sr * 0.014), 1)
        amplitude = np.clip(np.sqrt(note["amplitude"]), 0.25, 0.8)
        result[start:end] += amplitude * tone * attack * np.maximum(release, 0)
    return result.astype(np.float32)


def normalize(y: np.ndarray) -> np.ndarray:
    return y * (0.85 / max(float(np.max(np.abs(y))), 1e-6))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("project", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    project = json.loads((args.project / "project.json").read_text())
    notes = project["notes"]
    original, sr = sf.read(args.project / project["audioFile"], dtype="float32")
    if original.ndim > 1:
        original = original.mean(axis=1)
    duration = len(original) / sr
    score = render(notes, duration, sr)
    left, right = normalize(original), normalize(score)
    sf.write(args.output / "score-preview.wav", right, sr, subtype="PCM_16")
    sf.write(args.output / "original-reference.wav", left, sr, subtype="PCM_16")
    stereo = np.stack([left, right], axis=1)
    sf.write(args.output / "comparison-stereo.wav", stereo, sr, subtype="PCM_16")
    sf.write(args.output / "comparison-12-20s.wav", stereo[12 * sr:20 * sr], sr, subtype="PCM_16")
    # Sequential A/B works on mono speakers, with an explicit one-second pause.
    sf.write(args.output / "comparison-ab.wav", np.concatenate([left, np.zeros(sr), right]), sr, subtype="PCM_16")
    sf.write(args.output / "comparison-ab-12-20s.wav", np.concatenate([left[12 * sr:20 * sr], np.zeros(sr), right[12 * sr:20 * sr]]), sr, subtype="PCM_16")

    hop = int(sr * 0.01)
    times = (np.arange((len(original) + hop - 1) // hop) + 0.5) * hop / sr
    rms = np.array([np.sqrt(np.mean(original[i:i + hop] ** 2)) for i in range(0, len(original), hop)])
    active = rms > max(float(rms.max()) * 10 ** (-35 / 20), 1e-5)
    covered = np.zeros(len(times), dtype=bool)
    gaps, cursor = [], 0.
    for n in notes:
        if n["start"] - cursor >= 0.5:
            gaps.append({"start": cursor, "end": n["start"], "duration": n["start"] - cursor})
        cursor = max(cursor, n["start"] + n["duration"])
        covered |= (times >= n["start"]) & (times < n["start"] + n["duration"])
    if duration - cursor >= 0.5:
        gaps.append({"start": cursor, "end": duration, "duration": duration - cursor})
    for gap in gaps:
        mask = (times >= gap["start"]) & (times < gap["end"])
        gap["source_active_fraction"] = float(active[mask].mean()) if mask.any() else 0
    stats = {
        "duration": duration, "note_count": len(notes),
        "note_seconds": sum(n["duration"] for n in notes),
        "note_coverage": float(covered.mean()),
        "source_active_fraction": float(active.mean()),
        "source_activity_threshold": "-35 dB relative to peak 10 ms RMS; includes vocals and accompaniment",
        "active_source_without_tab_fraction": float((active & ~covered).sum() / max(1, active.sum())),
        "confidence_mean": float(np.mean([n["confidence"] for n in notes])),
        "low_confidence_notes": sum(n["confidence"] < 0.8 for n in notes),
        "shorter_than_150ms": sum(n["duration"] < 0.15 for n in notes),
        "median_note_duration": float(np.median([n["duration"] for n in notes])),
        "midi_range": [min(n["pitch"] for n in notes), max(n["pitch"] for n in notes)],
        "fret_pitch_consistent": all(TUNING[n["string"] - 1] + n["fret"] == n["pitch"] for n in notes),
        "longest_tab_gaps": sorted(gaps, key=lambda gap: gap["duration"], reverse=True)[:6],
        "warnings": project["warnings"],
        "interpretation": "Coverage and model confidence are NOT transcription accuracy. No isolated guitar or human reference TAB supplied.",
        "preview": "Deterministic additive plucked synthesis from string/fret; original timing and rests retained. No bend, vibrato or original guitar tone. Both channels independently peak-normalized to 0.85, with no time shift.",
    }
    (args.output / "metrics.json").write_text(json.dumps(stats, ensure_ascii=False, indent=2))
    with (args.output / "notes.csv").open("w", newline="", encoding="utf-8-sig") as file:
        writer = csv.writer(file)
        writer.writerow(["id", "pitch", "note", "start", "duration", "string", "fret", "confidence"])
        for n in notes:
            writer.writerow([n["id"], n["pitch"], name(n["pitch"]), n["start"], n["duration"], n["string"], n["fret"], n["confidence"]])
    lines = [project["title"], "Standard EADGBE; event columns, not rhythm notation.", "Exact timing: notes.csv", ""]
    for offset in range(0, len(notes), 16):
        for string, label in enumerate(["e", "B", "G", "D", "A", "E"], 1):
            lines.append(label + "|" + "".join((str(n["fret"]) if n["string"] == string else "-").ljust(5, "-") for n in notes[offset:offset + 16]) + "|")
        lines.append("")
    (args.output / "transcription.txt").write_text("\n".join(lines))
    print(json.dumps(stats, ensure_ascii=False, indent=2))

    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    import librosa
    import librosa.display
    from matplotlib.collections import LineCollection

    analysis = librosa.resample(original, orig_sr=sr, target_sr=22050)
    cqt = np.abs(librosa.cqt(analysis, sr=22050, hop_length=256, fmin=librosa.midi_to_hz(36), n_bins=60, bins_per_octave=12))
    db = librosa.amplitude_to_db(cqt, ref=np.max)
    plt.rcParams.update({"figure.facecolor": "#101416", "axes.facecolor": "#151b1e", "text.color": "#e7ecee", "axes.labelcolor": "#c9d3d5", "xtick.color": "#a8b7bb", "ytick.color": "#a8b7bb", "axes.edgecolor": "#455054", "font.size": 10})
    fig, axes = plt.subplots(3, 1, figsize=(15, 8), gridspec_kw={"height_ratios": [1, 2.5, 1]}, sharex=True)
    fig.suptitle(f"Mixed audio vs. actual TAB reconstruction | {duration:.2f} s / {len(notes)} notes", fontsize=17, x=0.06, ha="left")
    axes[0].plot(times, rms, color="#97a8b2", linewidth=0.8)
    axes[0].fill_between(times, 0, rms, where=covered, color="#b7e78c", alpha=0.75)
    axes[0].set_ylabel("Source RMS")
    axes[0].set_title("Green: intervals with a TAB note. Grey: source activity without a TAB note.", loc="left", fontsize=10)
    axes[1].imshow(db, origin="lower", aspect="auto", extent=[0, db.shape[1] * 256 / 22050, 35.5, 95.5], vmin=-65, vmax=0, cmap="magma")
    segments = [[(n["start"], n["pitch"]), (n["start"] + n["duration"], n["pitch"])] for n in notes]
    colors = ["#b7e78c" if n["confidence"] >= 0.8 else "#6ddaff" for n in notes]
    axes[1].add_collection(LineCollection(segments, colors=colors, linewidths=3))
    axes[1].set_ylim(36, 84)
    axes[1].set_yticks(list(range(36, 85, 12)), [name(p) for p in range(36, 85, 12)])
    axes[1].set_ylabel("Pitch / harmonics")
    axes[1].set_title("Source constant-Q spectrum + TAB notes (green >= 80% confidence, cyan < 80%). Harmonics are not reference notes.", loc="left", fontsize=10)
    sample_times = np.arange(0, len(score), 80) / sr
    axes[2].plot(sample_times, right[::80], color="#b7e78c", linewidth=0.5)
    axes[2].set_ylabel("TAB synthesis")
    axes[2].set_xlabel("Time in original audio (seconds)")
    axes[2].set_xlim(0, duration)
    for ax in axes:
        ax.grid(axis="x", color="#ffffff", alpha=0.1)
    fig.text(0.06, 0.015, f"{stats['note_seconds']:.2f} s of note durations ({100 * stats['note_coverage']:.1f}% coverage). These are diagnostics, not a measured guitar-transcription accuracy score.", fontsize=10, color="#edbb84")
    fig.tight_layout(rect=[0, 0.04, 1, 0.95])
    fig.savefig(args.output / "comparison.png", dpi=150)
    plt.close(fig)


if __name__ == "__main__":
    main()
