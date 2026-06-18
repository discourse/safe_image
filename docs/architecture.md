# Safe Image architecture and safety model

Safe Image is deliberately structured as a narrow boundary around untrusted image bytes. The public API lives on
`SafeImage`, but the implementation is split by responsibility:

- `lib/safe_image/api/metadata.rb` — public read-only operations (`probe`, `size`, `info`, animation checks, etc.).
- `lib/safe_image/api/transform.rb` — public image-producing operations. These require explicit `input:` and `output:`
  keywords and never replace a caller's source file in place.
- `lib/safe_image/operations.rb` — private backend orchestration shared by public writers.
- `lib/safe_image/processor.rb` — libvips thumbnail path.
- `lib/safe_image/image_magick_backend.rb` — ImageMagick argv construction under the bundled policy.
- `lib/safe_image/sandbox.rb` — Landlock dispatch schemas and worker serialization.
- `lib/safe_image/formats.rb` — Ruby-side format normalization and allowlists.
- `lib/safe_image/atomic_output.rb` — same-directory temporary output and atomic replacement helpers.

## Security invariants

Changes should preserve these rules:

1. `SafeImage.configure!(backend:, landlock:)` is mandatory before any operation. Backend and sandbox posture are a
   boot-time decision, not per-call convenience flags.
2. The configured backend is authoritative. There is no silent fallback from libvips to ImageMagick when a format fails.
3. Untrusted local paths pass `PathSafety` checks. Symlink components are rejected, output paths may not be directories,
   and input/output paths must be distinct.
4. Public writers require explicit output paths. No public API mutates the input file in place or shuffles files for the
   caller.
5. Output replacement goes through `AtomicOutput`, which writes a sibling temporary file and renames it into place so
   callers do not observe partial output.
6. External commands are always argv arrays. Never construct shell strings.
7. ImageMagick paths are prefixed with explicit coders (`jpeg:`, `png:`, etc.) and run only with the bundled restrictive
   `policy.xml`.
8. Pixel limits are enforced before full decode: libvips probes headers first and ImageMagick uses both probe checks and
   its `128MP` area limit.
9. SVG metadata probing remains bounded and non-rendering: byte/depth/element/attribute caps, unsafe encoding rejection,
   and root-dimension pixel caps all happen before parser results are trusted.
10. Remote fetching remains SSRF-hardened: DNS pinning, special-use IP blocking, redirect limits, and no direct decode
    from network sockets.

## Debugging model

- `SafeImage::CommandError` carries `command`, `status`, `stdout`, `stderr`, `category`, and optional `operation` so CI
  failures show whether the fault came from a timeout, output cap, exit status, sandbox command, or sandbox worker.
- Backend labels are centralized in `BackendLabel` so results consistently report `libvips-direct`, `imagemagick`, or
  `libvips-direct+cjpegli`.
- Landlock worker permissions come from `Sandbox::OPERATION_PATHS`. Add new operations there explicitly; do not infer
  readable/writable paths from arbitrary argument strings.

## Adding a new image-producing operation

1. Add a public method in `api/transform.rb` with explicit keywords.
2. Add private backend orchestration in `operations.rb`.
3. Add or reuse backend-specific argv/native helpers.
4. Add an explicit Landlock path schema in `Sandbox::OPERATION_PATHS`.
5. Route temporary outputs through `AtomicOutput`.
6. Normalize/validate formats with `Formats`.
7. Add contract and backend tests that exercise real fixtures rather than mocks.
