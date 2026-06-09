# frozen_string_literal: true

require "tmpdir"
require "zlib"
require_relative "../lib/safe_image"

FIXTURES = File.expand_path("fixtures/images", __dir__)
PNG = File.join(FIXTURES, "large_and_unoptimized.png")

# Append an ancillary tEXt chunk so we can prove a no-op downsize re-encodes the
# image rather than copying the untrusted input bytes (and their metadata)
# through verbatim.
def with_text_marker(src, dst, marker)
  data = File.binread(src)
  insert_at = data.rindex("IEND") - 4
  body = "tEXt".b + "Comment\x00".b + marker.b
  chunk = [body.bytesize - 4].pack("N") + body + [Zlib.crc32(body)].pack("N")
  File.binwrite(dst, data[0...insert_at] + chunk + data[insert_at..])
end

Dir.mktmpdir do |dir|
  # A no-shrink downsize to a different format must still re-encode, never copy.
  jpg = File.join(dir, "converted.jpg")
  SafeImage.downsize(PNG, jpg, "9999x9999>", backend: :vips, optimize: false, max_pixels: 100_000_000)
  raise "vips downsize copied PNG bytes to JPG output" unless SafeImage.type(jpg, max_pixels: 100_000_000) == :jpeg

  # A no-op same-format downsize must re-encode and drop input metadata too.
  marker = "SAFE-IMAGE-DOWNSIZE-MARKER"
  marked = File.join(dir, "marked.png")
  with_text_marker(PNG, marked, marker)
  raise "marker not injected" unless File.binread(marked).include?(marker)

  out = File.join(dir, "noop.png")
  SafeImage.downsize(marked, out, "200%", backend: :vips, optimize: false, max_pixels: 100_000_000)
  raise "vips downsize copied input metadata through" if File.binread(out).include?(marker)
end

puts "OK vips downsize re-encodes input"
