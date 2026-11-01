#!/bin/bash
# Installs the voice: a Python environment with Kokoro, plus the model and voice files.
# Safe to run again: it skips anything already in place.
set -euo pipefail

# Kept short on purpose: the speech data library fails on long folder paths.
DATA="$HOME/Library/Application Support/ReadItOut"
MODELS="https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0"
PACKAGES=(kokoro-onnx==0.6.1 soundfile==0.14.0)

mkdir -p "$DATA"
cd "$DATA"

# 1. Python environment. Uses uv when available (faster), otherwise python3's venv.
if [ ! -x venv/bin/python ]; then
    echo "Creating Python environment..."
    if command -v uv >/dev/null; then
        uv venv --python 3.11 venv
    else
        if ! command -v python3 >/dev/null; then
            echo "Python 3 is required. Install it from python.org or with Homebrew, then run this again." >&2
            exit 1
        fi
        python3 -m venv venv
    fi
fi

echo "Installing Kokoro..."
if command -v uv >/dev/null; then
    uv pip install --quiet --python venv/bin/python "${PACKAGES[@]}"
else
    venv/bin/python -m pip install --quiet --upgrade pip
    venv/bin/python -m pip install --quiet "${PACKAGES[@]}"
fi

# 2. Model and voices (about 350 MB). Downloaded to a partial file first, so an
#    interrupted download is never mistaken for a finished one.
for file in kokoro-v1.0.onnx voices-v1.0.bin; do
    if [ ! -s "$file" ]; then
        echo "Downloading $file..."
        curl --fail --location --progress-bar --output "$file.part" "$MODELS/$file"
        mv "$file.part" "$file"
    fi
done

# 3. Check that the voice actually loads.
echo "Checking the voice..."
venv/bin/python -c "
from kokoro_onnx import Kokoro
Kokoro('kokoro-v1.0.onnx', 'voices-v1.0.bin').create('Ready.', voice='bm_george', lang='en-gb')
"

echo "Voice installed in $DATA"
echo "Next: ./build.sh, then open build/ReadItOut.app"
