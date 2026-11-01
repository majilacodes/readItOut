"""ReadItOut speech helper.

Keeps Kokoro loaded and turns one sentence at a time into a WAV file.
Protocol: one JSON object per line on stdin, one JSON reply per line on stdout.
  request:  {"id": 1, "text": "Hello.", "speed": 1.0}
  reply:    {"id": 1, "path": "/.../cache/1.wav"}  or  {"id": 1, "error": "..."}
On startup it prints {"ready": true} once the model is loaded.
"""

import json
import os
import sys

# Keep the real stdout for replies, and send anything else that writes to
# stdout (including native libraries) to stderr so it can't corrupt the protocol.
reply_out = os.fdopen(os.dup(1), "w", buffering=1)
os.dup2(2, 1)
sys.stdout = sys.stderr

import soundfile as sf  # noqa: E402
from kokoro_onnx import Kokoro  # noqa: E402

DATA = os.path.expanduser("~/Library/Application Support/ReadItOut")
CACHE = os.path.join(DATA, "cache")
VOICE = "bm_george"


def send(message):
    reply_out.write(json.dumps(message) + "\n")


def main():
    os.makedirs(CACHE, exist_ok=True)
    for name in os.listdir(CACHE):
        os.remove(os.path.join(CACHE, name))

    kokoro = Kokoro(
        os.path.join(DATA, "kokoro-v1.0.onnx"),
        os.path.join(DATA, "voices-v1.0.bin"),
    )
    send({"ready": True})

    for line in sys.stdin:
        if not line.strip():
            continue
        request = json.loads(line)
        request_id = request["id"]
        try:
            samples, sample_rate = kokoro.create(
                request["text"],
                voice=request.get("voice", VOICE),
                speed=float(request.get("speed", 1.0)),
                lang="en-gb",
            )
            path = os.path.join(CACHE, f"{request_id}.wav")
            sf.write(path, samples, sample_rate)
            send({"id": request_id, "path": path})
        except Exception as error:  # report and keep serving
            send({"id": request_id, "error": str(error)})


if __name__ == "__main__":
    main()
