"""Deterministic monophonic transcription using pYIN, with onset-aware tracking."""
from __future__ import annotations

import subprocess
from pathlib import Path
from typing import Callable

import numpy as np
import soundfile as sf

MAX_DURATION = 180
ANALYSIS_RATE = 22050
HOP = 256


def decode_audio(source: Path, destination: Path) -> tuple[np.ndarray, int]:
    import imageio_ffmpeg

    if not source.is_file():
        raise ValueError("音频文件不存在。")
    if source.stat().st_size > 250 * 1024 * 1024:
        raise ValueError("文件超过 250 MB，请先截取 Solo 片段。")
    destination.parent.mkdir(parents=True, exist_ok=True)
    # Decode one extra second so that long inputs are rejected, never silently truncated.
    command = [imageio_ffmpeg.get_ffmpeg_exe(), "-nostdin", "-v", "error", "-y",
               "-i", str(source), "-t", str(MAX_DURATION + 1), "-vn", "-ac", "1",
               "-ar", "44100", "-c:a", "pcm_s16le", str(destination)]
    result = subprocess.run(command, capture_output=True, timeout=90)
    if result.returncode:
        raise ValueError("无法解码该音频，请使用有效的 WAV、AIFF、MP3 或 FLAC 文件。")
    audio, sr = sf.read(destination, dtype="float32")
    if len(audio) / sr > MAX_DURATION:
        raise ValueError(f"MVP 支持最长 {MAX_DURATION} 秒的 Solo，请先截取片段。")
    if len(audio) < sr * 0.1:
        raise ValueError("音频太短，至少需要 0.1 秒。")
    if not np.all(np.isfinite(audio)) or float(np.max(np.abs(audio))) < 1e-5:
        raise ValueError("音频没有可分析的有效信号。")
    return audio, sr


def track_notes(midi: np.ndarray, confidence: np.ndarray, rms: np.ndarray,
                onsets: set[int], frame_seconds: float, duration: float) -> list[dict]:
    """Smooth isolated pitch jitter; preserve repeated-note attacks and real rests."""
    valid = np.isfinite(midi) & (confidence >= 0.50) & (rms > max(float(rms.max()) * 0.012, 1e-5))
    quantized = np.full(len(midi), -1, dtype=int)
    quantized[valid] = np.rint(midi[valid]).astype(int)
    smooth = quantized.copy()
    for i in range(2, len(quantized) - 2):
        window = quantized[i - 2:i + 3]
        if valid[i] and np.all(window >= 0) and not any(k in onsets for k in range(i - 2, i + 3)):
            smooth[i] = int(np.median(window))

    segments: list[tuple[int, int, int]] = []
    start = 0
    for i in range(1, len(smooth) + 1):
        boundary = i == len(smooth) or smooth[i] != smooth[start]
        repeated_attack = i in onsets and (i - start) * frame_seconds >= 0.085
        if boundary or repeated_attack:
            if smooth[start] >= 0:
                segments.append((start, i, int(smooth[start])))
            start = i

    merged: list[tuple[int, int, int]] = []
    for start, end, pitch in segments:
        if merged and merged[-1][2] == pitch and (start - merged[-1][1]) * frame_seconds <= 0.035 and not any(
            k in onsets for k in range(merged[-1][1], start + 1)
        ):
            old = merged.pop()
            merged.append((old[0], end, pitch))
        else:
            merged.append((start, end, pitch))

    notes = []
    for start, end, pitch in merged:
        begin = start * frame_seconds
        length = min(end * frame_seconds, duration) - begin
        if length < 0.07:
            continue
        notes.append(dict(id=f"note-{len(notes) + 1}", pitch=pitch, start=round(begin, 5),
                          duration=round(length, 5), confidence=round(float(np.mean(confidence[start:end])), 4),
                          amplitude=round(float(np.mean(rms[start:end])), 4), string=0, fret=0, locked=False))
    return notes


def analyze(source: Path, output: Path, progress: Callable[[float, str], None] = lambda *_: None) -> dict:
    progress(0.04, "正在解码音频")
    audio, sr = decode_audio(source, output)
    duration = len(audio) / sr
    progress(0.16, "正在准备音高分析")
    import librosa

    normalized = audio / max(float(np.max(np.abs(audio))), 1e-5) * 0.95
    analysis = librosa.resample(normalized, orig_sr=sr, target_sr=ANALYSIS_RATE)
    progress(0.25, "正在识别音高 · 首次运行需要初始化")
    f0, _, probabilities = librosa.pyin(
        analysis, fmin=70, fmax=1500, sr=ANALYSIS_RATE,
        frame_length=2048, hop_length=HOP, fill_na=np.nan,
    )
    progress(0.78, "正在整理音符与起音")
    midi = librosa.hz_to_midi(f0)
    rms = librosa.feature.rms(y=analysis, frame_length=2048, hop_length=HOP)[0]
    onset_frames = set(int(x) for x in librosa.onset.onset_detect(
        y=analysis, sr=ANALYSIS_RATE, hop_length=HOP, backtrack=False,
    ))
    count = min(len(midi), len(rms))
    raw = track_notes(midi[:count], np.nan_to_num(probabilities[:count]), rms[:count],
                      onset_frames, HOP / ANALYSIS_RATE, duration)
    notes = [n for n in raw if 40 <= n["pitch"] <= 88]
    warnings = []
    if len(notes) != len(raw):
        warnings.append(f"{len(raw) - len(notes)} 个音符超出标准调弦 24 品范围，已略过。")
    if not notes:
        raise ValueError("没有找到稳定的单音旋律。请使用干净的 Guitar Solo / Stem，避免完整混音。")
    uncertain = sum(n["confidence"] < 0.8 for n in notes)
    if uncertain:
        warnings.append(f"{uncertain} 个音符置信度低于 80%，建议试听后修正。")
    peaks = [round(float(np.max(np.abs(chunk))), 5) for chunk in np.array_split(normalized, min(900, len(normalized)))]
    progress(0.96, "正在生成分析结果")
    return dict(notes=notes, waveform=peaks, duration=duration, sampleRate=sr,
                warnings=warnings, audioPath=str(output))
