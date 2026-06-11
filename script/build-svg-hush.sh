#!/usr/bin/env bash
# Builds the bundled svg-hush binaries from a pinned version into vendor/svg-hush/.
#
# The gem ships prebuilt binaries (no Rust toolchain at install). Linux builds
# are static musl via cargo-zigbuild, so one binary per arch runs on any distro
# (Alpine, Debian, old/new glibc) with no dynamic dependencies — and they
# cross-compile from a single host (zig is the linker; no per-arch gcc).
#
# Prereqs (one-time):
#   rustup target add x86_64-unknown-linux-musl aarch64-unknown-linux-musl
#   cargo install cargo-zigbuild        # needs `zig` on PATH (ziglang.org)
#
# Usage:
#   script/build-svg-hush.sh                                   # both Linux arches
#   SVGHUSH_VERSION=0.9.6 script/build-svg-hush.sh x86_64-unknown-linux-musl
#
# macOS is not built here: it needs the Apple SDK (and `lipo` for a universal
# binary). Build svg-hush-x86_64-darwin / svg-hush-arm64-darwin on a macOS CI
# runner (or via cargo-zigbuild with SDKROOT set), then `lipo -create` them into
# svg-hush-universal-darwin.
set -euo pipefail

SVGHUSH_VERSION="${SVGHUSH_VERSION:-0.9.6}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="$ROOT/vendor/svg-hush"
mkdir -p "$DEST"

# Rust target triple -> gem platform slug (matches SvgHush.platform_slug).
slug_for() {
  case "$1" in
    x86_64-unknown-linux-musl|x86_64-unknown-linux-gnu) echo "x86_64-linux" ;;
    aarch64-unknown-linux-musl|aarch64-unknown-linux-gnu) echo "aarch64-linux" ;;
    *) echo "" ;;
  esac
}

targets=("$@")
if [ ${#targets[@]} -eq 0 ]; then
  targets=(x86_64-unknown-linux-musl aarch64-unknown-linux-musl)
fi

# Fetch the pinned source once, build each target against it.
src="$(mktemp -d)"
trap 'rm -rf "$src"' EXIT
cargo install svg-hush --version "$SVGHUSH_VERSION" --locked --no-track \
  --root "$src/install" --bin svg-hush >/dev/null 2>&1 || true # warms the registry cache; ignore
# Build from a checkout so we can pick the linker (cargo install can't use zigbuild).
git clone --depth 1 --branch "$SVGHUSH_VERSION" https://github.com/cloudflare/svg-hush "$src/repo" 2>/dev/null \
  || git clone --depth 1 https://github.com/cloudflare/svg-hush "$src/repo"

for target in "${targets[@]}"; do
  slug="$(slug_for "$target")"
  if [ -z "$slug" ]; then echo "!! unknown target $target, skipping"; continue; fi
  echo "== building svg-hush $SVGHUSH_VERSION for $target -> svg-hush-$slug (static musl)"
  ( cd "$src/repo" && cargo zigbuild --release --locked --target "$target" )
  cp "$src/repo/target/$target/release/svg-hush" "$DEST/svg-hush-$slug"
  chmod +x "$DEST/svg-hush-$slug"
done

echo "== done. vendored:"
ls -la "$DEST"
echo "Regenerate $DEST/THIRD-PARTY-LICENSES.txt with cargo-about before release."
