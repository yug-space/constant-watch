"""Original seamless ambient pad. No samples, recordings, or external assets."""
import math
import wave
from array import array
from pathlib import Path

rate, duration = 24000, 48
# Slow major-ninth and minor-seventh voicings, with shared notes between chords.
chords = [(146.832, 184.997, 220, 277.183, 329.628),
          (123.471, 146.832, 184.997, 220, 277.183),
          (97.999, 146.832, 184.997, 246.942, 293.665),
          (110, 164.814, 220, 246.942, 329.628)]
frames = array('h')
peak = 0.0
for i in range(rate * duration):
    t = i / rate
    sample = 0.0
    for c, chord in enumerate(chords):
        distance = ((t - c * 12 + 24) % 48) - 24
        if abs(distance) >= 12:
            continue
        envelope = 0.5 + 0.5 * math.cos(math.pi * distance / 12)
        for v, hz in enumerate(chord):
            # Integer cycles per loop make the waveform and its slope continuous.
            hz = round(hz * duration) / duration
            angle = 2 * math.pi * hz * t
            breath = 0.93 + 0.07 * math.sin(2 * math.pi * t / 48 + v)
            sample += envelope * breath * (math.sin(angle) + 0.13 * math.sin(2 * angle) + 0.025 * math.sin(3 * angle)) / 6
    peak = max(peak, abs(sample))
    frames.append(round(sample * 0.3 * 32767))
path = Path(__file__).resolve().parents[1] / 'native/Resources/OnboardingAmbience.wav'
with wave.open(str(path), 'wb') as output:
    output.setnchannels(1)
    output.setsampwidth(2)
    output.setframerate(rate)
    output.writeframes(frames.tobytes())
print(f'{path}: {duration}s, peak={peak * 0.3:.3f}, seamless loop')
