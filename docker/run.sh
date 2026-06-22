#!/bin/bash
# Runs the test suite inside a Debian bookworm container against the stock
# packaged libvips (8.14), validating both the oldest supported libvips and
# native-helper build/install.
set -euo pipefail

cd "$(dirname "$0")/.."
docker build -f docker/bookworm.dockerfile -t safe-image-bookworm-test .
exec docker run --rm safe-image-bookworm-test
