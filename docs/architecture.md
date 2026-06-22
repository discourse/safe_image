# Safe Image architecture and safety model

Safe Image is deliberately structured as a narrow boundary around untrusted image bytes. The public API lives on
`SafeImage`, but the implementation is split by responsibility:

- `lib/safe_image/api/metadata.rb` — public read-only method signatures (`probe`, `size`, `info`, animation checks,
  etc.) that delegate to operation objects.
- `lib/safe_image/api/transform.rb` — public image-producing method signatures. These require explicit `input:` and
  `output:` keywords and never replace a caller's source file in place.
- `lib/safe_image/metadata_operations.rb` and `lib/safe_image/transform_operations.rb` — inline Ruby orchestration for
  public operations. They do not load libvips and they are not proxied through a Ruby sandbox worker.
- `lib/safe_image/operations.rb` — private backend orchestration shared by public writers.
- `lib/safe_image/processor.rb` and `lib/safe_image/native.rb` — libvips orchestration that shells out to the bundled
  `safe_image_vips_helper`; the Ruby process never loads libvips.
- `lib/safe_image/image_magick_backend.rb` — ImageMagick argv construction under the bundled policy.
- `lib/safe_image/sandbox.rb` — optional Landlock capture for child commands/helpers, with explicit read/write grants.
- `lib/safe_image/formats.rb` — Ruby-side format normalization and allowlists.
- `lib/safe_image/staged_output.rb` — same-directory temporary output and staged replacement helpers.

## Security invariants

Changes should preserve these rules:

1. `SafeImage.configure!(backend:, landlock:)` is mandatory before any operation. Backend and sandbox posture are a
   boot-time decision, not per-call convenience flags.
2. The configured backend is authoritative. There is no silent fallback from libvips to ImageMagick when a format fails.
3. Untrusted local paths pass `PathSafety` checks. Symlink components are rejected, output paths may not be directories,
   and input/output paths must be distinct.
4. Public writers require explicit output paths. No public API mutates the input file in place or shuffles files for the
   caller.
5. Output replacement goes through `StagedOutput`, which writes a sibling temporary file and renames it into place so
   callers do not observe partial output.
6. External commands are always argv arrays. Never construct shell strings.
7. ImageMagick paths are prefixed with explicit coders (`jpeg:`, `png:`, etc.) and run only with the bundled restrictive
   `policy.xml`.
8. Pixel limits are enforced before full decode: libvips probes headers first and ImageMagick uses both probe checks and
   its `128MP` area limit.
9. SVG metadata probing remains bounded and non-rendering: byte/depth/element/attribute caps, unsafe encoding rejection,
   and root-dimension pixel caps all happen before parser results are trusted. This Nokogiri/libxml2 parse runs in the
   Ruby process; Landlock containment is for child helpers and tools, not this parser.
10. Remote fetching remains SSRF-hardened: DNS pinning, special-use IP blocking, redirect limits, and no direct decode
    from network sockets.

## Debugging model

- `SafeImage::CommandError` carries `command`, `status`, `stdout`, `stderr`, `category`, and optional `operation` so CI
  failures show whether the fault came from a timeout, output cap, exit status, sandboxed command/helper, or native
  helper error.
- Backend labels are centralized in `BackendLabel` so results consistently report `libvips-helper`, `imagemagick`, or
  `libvips-helper+cjpegli`.
- With `landlock: true`, child commands/helpers get explicit readable and writable path lists at each call site. Add new
  tool/helper invocations deliberately; do not infer readable/writable paths from arbitrary argument strings.

## Adding a new image-producing operation

1. Add a public method in `api/transform.rb` with explicit keywords.
2. Add the inline implementation to `TransformOperations`.
3. Add private backend orchestration in `operations.rb` if it is shared across backends.
4. Add or reuse backend-specific argv/native helpers.
5. If the operation shells out, pass explicit Landlock `read:`/`write:` grants to the child command/helper.
6. Route temporary outputs through `StagedOutput`.
7. Normalize/validate formats with `Formats`.
8. Add contract and backend tests that exercise real fixtures rather than mocks.
