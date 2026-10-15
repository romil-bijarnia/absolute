#!/usr/bin/env python3
"""Synthesise Absolute's sound theme: short, soft system sounds of our own.

Usage: sounds_absolute.py OUT_DIR
Writes OUT_DIR/index.theme and OUT_DIR/stereo/*.wav under the freedesktop sound
naming specification, so Plasma plays them for its notification events once
kdeglobals [Sounds] Theme=absolute is set. Every sound is generated here from
sine tones and filtered noise; nothing is sampled from any other system.
"""
import struct
import sys
import wave
from pathlib import Path

import numpy as np

RATE = 48000


def envelope(n: int, attack: float, decay: float) -> np.ndarray:
    t = np.arange(n) / RATE
    env = np.minimum(t / max(attack, 1e-4), 1.0) * np.exp(-t / decay)
    return env


def tone(freq: float, seconds: float, decay: float, attack: float = 0.004, harmonics=((1, 1.0), (2, 0.25), (3, 0.08))) -> np.ndarray:
    n = int(seconds * RATE)
    t = np.arange(n) / RATE
    signal = np.zeros(n)
    for mult, amp in harmonics:
        signal += amp * np.sin(2 * np.pi * freq * mult * t)
    return signal * envelope(n, attack, decay)


def noise(seconds: float, decay: float, lowpass: int = 24, attack: float = 0.002) -> np.ndarray:
    n = int(seconds * RATE)
    rng = np.random.default_rng(7)
    raw = rng.standard_normal(n)
    kernel = np.ones(lowpass) / lowpass
    soft = np.convolve(raw, kernel, mode="same")
    return soft * envelope(n, attack, decay)


def sequence(parts, gap: float = 0.0) -> np.ndarray:
    pieces = []
    silence = np.zeros(int(gap * RATE))
    for i, part in enumerate(parts):
        pieces.append(part)
        if i < len(parts) - 1 and gap > 0:
            pieces.append(silence)
    return np.concatenate(pieces)


def overlay(a: np.ndarray, b: np.ndarray, offset: float) -> np.ndarray:
    start = int(offset * RATE)
    n = max(len(a), start + len(b))
    out = np.zeros(n)
    out[: len(a)] += a
    out[start : start + len(b)] += b
    return out


def write(path: Path, signal: np.ndarray, gain: float = 0.5) -> None:
    peak = np.max(np.abs(signal)) or 1.0
    data = np.clip(signal / peak * gain, -1, 1)
    stereo = np.repeat(data[:, None], 2, axis=1)
    frames = (stereo * 32767).astype("<i2").tobytes()
    with wave.open(str(path), "wb") as out:
        out.setnchannels(2)
        out.setsampwidth(2)
        out.setframerate(RATE)
        out.writeframes(frames)


def build(out: Path) -> None:
    stereo = out / "stereo"
    stereo.mkdir(parents=True, exist_ok=True)
    # The alert: two close notes with a round body, the sound of a dialog.
    alert = overlay(tone(587.33, 0.42, 0.12), tone(880.0, 0.36, 0.1), 0.05)
    # A single soft note for information.
    info = tone(659.25, 0.35, 0.11)
    # A rising pair for a new message.
    message = sequence([tone(783.99, 0.18, 0.07), tone(1046.5, 0.3, 0.1)], gap=0.02)
    # Device in: up; device out: down.
    device_in = sequence([tone(523.25, 0.14, 0.06), tone(783.99, 0.22, 0.08)], gap=0.01)
    device_out = sequence([tone(783.99, 0.14, 0.06), tone(523.25, 0.22, 0.08)], gap=0.01)
    # Emptying the trash: a crumple of filtered noise.
    trash = overlay(noise(0.45, 0.14, lowpass=40), noise(0.2, 0.05, lowpass=8), 0.12)
    # Screen capture: a click with a short noise tail.
    capture = overlay(noise(0.06, 0.012, lowpass=3), tone(1800, 0.08, 0.02, harmonics=((1, 1.0),)), 0.0)
    # Volume change: a short pop.
    pop = tone(1000, 0.07, 0.018, harmonics=((1, 1.0),))
    # Login: a short bright chord; logout: the same, descending.
    login = overlay(overlay(overlay(tone(523.25, 1.2, 0.4), tone(659.25, 1.1, 0.4), 0.08), tone(783.99, 1.0, 0.4), 0.16), tone(1046.5, 1.1, 0.5), 0.24)
    logout = overlay(overlay(tone(783.99, 0.6, 0.25), tone(659.25, 0.6, 0.25), 0.1), tone(523.25, 0.8, 0.35), 0.2)
    completion = sequence([tone(880.0, 0.12, 0.05), tone(1174.66, 0.25, 0.1)], gap=0.01)
    failure = sequence([tone(392.0, 0.2, 0.08), tone(311.13, 0.35, 0.12)], gap=0.02)

    files = {
        "bell": alert,
        "bell-window-system": alert,
        "dialog-error": alert,
        "dialog-error-serious": alert,
        "dialog-error-critical": alert,
        "dialog-warning": alert,
        "dialog-question": alert,
        "dialog-information": info,
        "message-new-instant": message,
        "message-new-email": message,
        "message": message,
        "device-added": device_in,
        "device-removed": device_out,
        "trash-empty": trash,
        "screen-capture": capture,
        "audio-volume-change": pop,
        "desktop-login": login,
        "desktop-logout": logout,
        "completion-success": completion,
        "completion-fail": failure,
        "battery-low": alert,
        "battery-caution": alert,
        "power-plug": device_in,
        "power-unplug": device_out,
    }
    for name, signal in files.items():
        write(stereo / f"{name}.wav", signal)
    (out / "index.theme").write_text(
        "[Sound Theme]\nName=Absolute\nComment=Absolute's own system sounds\nDirectories=stereo\n\n[stereo]\nOutputProfile=stereo\n"
    )


if __name__ == "__main__":
    build(Path(sys.argv[1]))
