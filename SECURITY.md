# Security Policy

Safe Image is a hardened image-processing boundary for untrusted uploads, not a proof that hostile image bytes are harmless.

## Supported versions

Security fixes are expected to land on `main` until the gem has tagged releases. Once releases exist, report against the latest released version unless you can reproduce on `main` as well.

## Threat model

Safe Image assumes image input may be attacker-controlled. The library is designed to reduce the number of places an application touches those bytes and to remove common image-processing foot-guns:

- shell-free external command execution using argv arrays
- allowlisted command environment
- bounded command output and process-group timeout cleanup
- explicit libvips loader selection for supported raster formats
- no silent fallback from libvips to generic ImageMagick decoding
- restrictive ImageMagick policy disabling delegates, filters, `@file`, remote URL coders, Ghostscript-backed formats, and dangerous pseudo-formats
- symlink rejection for untrusted local input/output paths
- remote fetch SSRF hardening: scheme/port restrictions, special-use IP blocking, DNS pinning, redirect limits, HTTPS-to-HTTP rejection, header allowlists, content-type/extension agreement, and probe-before-yield
- bounded SVG metadata parsing and conservative SVG sanitising without handing SVG to ImageMagick for probing
- optional Linux Landlock/seccomp subprocess sandboxing

## Non-goals

Safe Image does not claim that parsing hostile images in-process is memory-safe. Raster decoders such as libjpeg, libpng, libwebp, libheif, libvips loaders, and ImageMagick coders still parse attacker-controlled bytes. A decoder memory-corruption bug or pathological resource-consumption bug is still possible.

The honest claim is defense-in-depth:

- without Landlock: centralized and hardened image processing with major delegate/protocol/policy foot-guns removed
- with Landlock: the same hardening plus a kernel containment boundary around subprocess-based public operations

If your deployment needs a hard isolation boundary, enable sandbox execution and run image processing away from your main web worker process.

## Reporting vulnerabilities

Please report suspected security issues privately to `sam@discourse.org`.

Include:

- affected version or commit
- input file or minimized reproducer, if shareable
- operation/API called
- expected vs actual result
- whether Landlock sandboxing was enabled
- host OS, kernel, libvips, ImageMagick, and optimizer tool versions

Do not open a public issue for an exploitable crash, sandbox escape, SSRF bypass, arbitrary file read/write, command execution bug, or denial-of-service vector until there has been time to patch.
