# frozen_string_literal: true

require "pathname"

module SafeImage
  # Standalone SVG sanitisation delegated to Cloudflare's svg-hush (a memory-safe,
  # fuzzed Rust filter) instead of a bespoke Ruby allowlist sanitizer. We bundle a
  # prebuilt per-platform binary and exec it through the same argv-only + Landlock
  # path as the other external tools (magick, jpegoptim, ...): no FFI, crash
  # isolation, and the sandbox wraps a memory-safe binary.
  #
  # Scope: output is document-safe — safe to serve as an <img>/CSS-url/file. It is
  # NOT made safe to splice into a host HTML DOM (no id/class namespacing or
  # <style> scoping); svg-hush strips scripting, off-origin references and unknown
  # elements/attributes, which is the standalone guarantee this gem now offers.
  module SvgHush
    module_function

    # Reuses SvgMetadata's pre-checks (byte cap, encoding rejection, pixel cap) so
    # the limits and the InvalidImageError/LimitError hierarchy match the rest of
    # the gem; svg-hush only does the element/attribute/URL filtering.
    def sanitize!(path, max_pixels: nil, timeout: Runner::DEFAULT_TIMEOUT)
      path = Pathname.new(SvgMetadata.safe_svg_path(path))

      # Byte cap + unsafe-encoding rejection. svg-hush only groks UTF-8/16/latin1,
      # and our byte scans assume ASCII-transparency, so keep rejecting the rest.
      SvgMetadata.read_svg(path.to_s)
      begin
        SvgMetadata.dimensions(path.to_s, max_pixels: max_pixels)
      rescue InvalidImageError => e
        raise unless e.message.include?("dimensions are missing")
      end

      out_path = "#{path}.svghush-#{Process.pid}"
      begin
        # Runner sandboxes (Landlock) automatically when configure!(landlock: true);
        # read the input + the binary, write the sibling output file.
        Runner.run!(
          [binary, path.to_s, out_path],
          timeout: timeout,
          read: [path.to_s, binary],
          write: [path.dirname.to_s]
        )
        raise InvalidImageError, "svg-hush produced no output" unless File.size?(out_path)
        File.rename(out_path, path.to_s)
      rescue CommandError => e
        # svg-hush rejects malformed / non-SVG / unsupported-encoding input with a
        # non-zero exit; surface it inside our error hierarchy.
        raise InvalidImageError, "invalid SVG: #{e.message}"
      ensure
        File.unlink(out_path) if File.exist?(out_path)
      end

      { format: "svg", sanitized: true, filesize: File.size(path.to_s) }
    end

    # Bundled prebuilt binary for the running platform. Fails loudly on an
    # unbundled platform rather than compiling at install (preserving the
    # no-toolchain-install invariant). Built by script/build-svg-hush.sh.
    def binary
      @binary ||= begin
        candidate = Pathname.new(__dir__).join("..", "..", "vendor", "svg-hush", "svg-hush-#{platform_slug}").expand_path
        unless candidate.file? && candidate.executable?
          raise Error, "no bundled svg-hush binary for platform #{platform_slug} (looked for #{candidate})"
        end
        candidate.to_s
      end
    end

    def platform_slug
      cpu = RbConfig::CONFIG["host_cpu"]
      cpu = "aarch64" if %w[arm64 aarch64].include?(cpu)
      cpu = "x86_64" if %w[x86_64 amd64].include?(cpu)
      os = RbConfig::CONFIG["host_os"].match?(/darwin/) ? "darwin" : "linux"
      "#{cpu}-#{os}"
    end
  end
end
