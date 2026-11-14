#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
OUT="$ROOT/dist"
mkdir -p "$OUT"
rm -f "$OUT/kobo-weather-plugin.zip"
cd "$ROOT"
zip -qr "$OUT/kobo-weather-plugin.zip" \
  README.md config.example.lua weather.koplugin \
  -x '*/__pycache__/*' '*.pyc'
printf 'Created %s\n' "$OUT/kobo-weather-plugin.zip"
