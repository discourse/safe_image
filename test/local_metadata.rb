# frozen_string_literal: true

require "tmpdir"
require_relative "../lib/safe_image"

FIXTURES = File.expand_path("fixtures/images", __dir__)
JPG = File.join(FIXTURES, "huge.jpg")
PNG = File.join(FIXTURES, "large_and_unoptimized.png")
GIF = File.join(FIXTURES, "animated.gif")
WEBP = File.join(FIXTURES, "animated.webp")

raise "jpg type mismatch" unless SafeImage.type(JPG) == :jpeg
raise "png type mismatch" unless SafeImage.type(PNG) == :png
raise "jpg size mismatch" unless SafeImage.size(JPG) == [8900, 8900]
raise "png dimensions mismatch" unless SafeImage.dimensions(PNG) == [2032, 1312]
raise "jpg orientation mismatch" unless SafeImage.orientation(JPG).to_i == 1
raise "gif animated mismatch" unless SafeImage.animated?(GIF, max_pixels: 10_000_000)
raise "webp animated mismatch" unless SafeImage.animated?(WEBP, max_pixels: 10_000_000)

info = SafeImage.info(JPG, animated: true, orientation: true, max_pixels: 100_000_000)
raise "info type mismatch" unless info.type == :jpeg
raise "info size mismatch" unless info.size == [8900, 8900]
raise "info animated mismatch" unless info.animated == false
raise "info orientation mismatch" unless info.orientation.to_i == 1

puts "OK local metadata helpers"
