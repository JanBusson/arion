#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(dirname -- "$script_dir")
fixture_port=${ARION_AUDIO_FIXTURE_PORT:-18081}
flutter_bin=${FLUTTER_BIN:-flutter}

python3 "$script_dir/web_audio_fixture.py" --port "$fixture_port" &
fixture_pid=$!
trap 'kill "$fixture_pid" 2>/dev/null || true' EXIT INT TERM

attempt=0
until curl --fail --silent "http://127.0.0.1:$fixture_port/health" >/dev/null; do
  attempt=$((attempt + 1))
  if [ "$attempt" -ge 20 ]; then
    echo "Audio fixture did not become ready." >&2
    exit 1
  fi
  sleep 0.25
done

cd "$repo_root/client"
"$flutter_bin" test --platform chrome \
  --dart-define="ARION_AUDIO_FIXTURE_URL=http://127.0.0.1:$fixture_port" \
  test/playback/just_audio_adapter_web_test.dart
