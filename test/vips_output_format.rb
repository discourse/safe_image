# frozen_string_literal: true

require "tmpdir"
require_relative "../lib/safe_image"

FIXTURES = File.expand_path("fixtures/images", __dir__)
PNG = File.join(FIXTURES, "large_and_unoptimized.png")

Dir.mktmpdir do |dir|
  out = File.join(dir, "converted.jpg")
  SafeImage.downsize(PNG, out, "9999x9999>", backend: :vips, optimize: false, max_pixels: 100_000_000)
  raise "vips downsize copied PNG bytes to JPG output" unless SafeImage.type(out, max_pixels: 100_000_000) == :jpeg
end

puts "OK vips output format consistency"
