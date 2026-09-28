"""D09 audible WAV delivery, matching consumer lib/protocol/beacon_protocol.dart.

48 kHz mono PCM16; 40 ms slots (20 ms tone + 20 ms quiet), 96-sample
ramps, amplitude .6, three frames, 100 ms padding before each and after all.
"""
from io import BytesIO
import math
import struct
import wave
from functools import lru_cache


@lru_cache(maxsize=2)
def symbol_pcm(bit):
    frequency = 5000 if bit else 4000
    samples = []
    for i in range(1920):
        ramp = max(0.0, min(1.0, i / 96, (960 - i) / 96))
        value = .6 * ramp * math.sin(2 * math.pi * frequency * i / 48000) if i < 960 else 0
        scaled = value * 32767
        samples.append(math.floor(scaled + .5) if scaled >= 0 else math.ceil(scaled - .5))
    return struct.pack('<1920h', *samples)


def frame_bytes(payload_id):
    if not 0 <= payload_id <= 0xFFFFFF:
        raise ValueError('Beacon ID must be 24 bits')
    body = payload_id.to_bytes(3, 'big')
    crc = 0
    for byte in body:
        crc ^= byte
        for _ in range(8):
            crc = ((crc << 1) ^ (7 if crc & 128 else 0)) & 255
    return bytes([0xCD, 0xA8]) + body + bytes([crc])


def render_wav(payload_id):
    frame = b''.join(symbol_pcm(byte >> bit & 1) for byte in frame_bytes(payload_id) for bit in range(7, -1, -1))
    quiet = bytes(9600)
    out = BytesIO()
    with wave.open(out, 'wb') as wav:
        wav.setparams((1, 2, 48000, 0, 'NONE', 'not compressed'))
        wav.writeframes((quiet + frame) * 3 + quiet)
    return out.getvalue()
