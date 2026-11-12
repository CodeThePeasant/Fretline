import numpy as np
import pytest
import soundfile as sf
import subprocess
import imageio_ffmpeg
from guitartab.transcribe import analyze, decode_audio, track_notes


def test_tracking_preserves_repeated_attack_and_rest():
    midi = np.array([64.] * 20 + [np.nan] * 10 + [66.] * 20)
    notes = track_notes(midi, np.ones(50), np.ones(50), {10}, 0.01, 0.5)
    assert [n["pitch"] for n in notes] == [64, 64, 66]
    assert notes[1]["start"] == 0.1
    assert notes[2]["start"] == 0.3


def test_filters_short_jitter():
    midi = np.array([64.] * 20 + [65.] + [64.] * 20)
    notes = track_notes(midi, np.ones(41), np.ones(41), set(), 0.01, 0.41)
    assert len(notes) == 1
    assert notes[0]["pitch"] == 64


def test_rejects_silence(tmp_path):
    source = tmp_path / "silence.wav"
    sf.write(source, np.zeros(44100), 44100)
    with pytest.raises(ValueError, match="有效信号"):
        decode_audio(source, tmp_path / "decoded.wav")


@pytest.mark.parametrize("extension", ["wav", "aiff", "mp3", "flac"])
def test_supported_formats_and_stereo_downmix(tmp_path, extension):
    sr = 44100
    t = np.arange(sr // 4) / sr
    tone = 0.4 * np.sin(2 * np.pi * 330 * t)
    original = tmp_path / "original.wav"
    sf.write(original, np.stack([tone, tone * 0.6], axis=1), sr)
    source = tmp_path / f"input.{extension}"
    subprocess.run([imageio_ffmpeg.get_ffmpeg_exe(), "-v", "error", "-y", "-i", str(original), str(source)], check=True)
    audio, rate = decode_audio(source, tmp_path / "decoded.wav")
    assert rate == sr
    assert audio.ndim == 1
    assert abs(len(audio) / rate - 0.25) < 0.05


def test_audio_to_notes(tmp_path):
    sr = 44100
    parts = [np.zeros(int(sr * 0.2))]
    for pitch in [64, 66, 68, 69, 71]:
        t = np.arange(int(sr * 0.45)) / sr
        frequency = 440 * 2 ** ((pitch - 69) / 12)
        # A decaying, harmonic-rich pluck, rather than feeding MIDI into the engine.
        signal = sum(np.sin(2 * np.pi * frequency * h * t) / h**2 for h in range(1, 6))
        envelope = np.minimum(t / 0.008, 1) * np.exp(-2 * t)
        parts.extend([0.5 * signal * envelope, np.zeros(int(sr * 0.1))])
    source = tmp_path / "phrase.wav"
    sf.write(source, np.concatenate(parts), sr)
    result = analyze(source, tmp_path / "playback.wav")
    assert [n["pitch"] for n in result["notes"]] == [64, 66, 68, 69, 71]
    assert abs(result["notes"][0]["start"] - 0.2) < 0.08
    assert all(0.32 < n["duration"] < 0.55 for n in result["notes"])
    assert result["sampleRate"] == 44100
    assert len(result["waveform"]) == 900
    assert (tmp_path / "playback.wav").is_file()
