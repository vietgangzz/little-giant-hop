#!/bin/sh
# Renders every sound and converts it to CAF for the app bundle (all stereo 44.1 kHz).
set -e
cd "$(dirname "$0")/.."
python3 tools/synth.py build/sounds "$@"
for f in build/sounds/*.wav; do
  name=$(basename "${f%.wav}")
  codec=LEI16
  [ "$name" = music ] && codec=alac  # lossless, half the size; SFX stay raw PCM
  afconvert -f caff -d "$codec" "$f" "LittleGiantHop/Resources/Sounds/$name.caf"
done
ls -la LittleGiantHop/Resources/Sounds
