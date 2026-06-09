# frozen_string_literal: true

require "tmpdir"
require_relative "../lib/safe_image"

FIXTURES = File.expand_path("fixtures/images", __dir__)
JPG = File.join(FIXTURES, "huge.jpg")

Dir.mktmpdir do |dir|
  input_link = File.join(dir, "input.jpg")
  File.symlink(JPG, input_link)

  begin
    SafeImage.probe(input_link)
    abort "probe accepted symlink input"
  rescue SafeImage::UnsafePathError
  end

  output = File.join(dir, "out.jpg")
  victim = File.join(dir, "victim.jpg")
  File.write(victim, "victim")
  File.symlink(victim, output)

  begin
    SafeImage.thumbnail(input: JPG, output: output, width: 10, height: 10)
    abort "thumbnail accepted symlink output"
  rescue SafeImage::UnsafePathError
  end
  raise "symlink output target changed" unless File.read(victim) == "victim"

  subdir = File.join(dir, "subdir")
  real_outside = File.join(dir, "outside")
  Dir.mkdir(real_outside)
  File.symlink(real_outside, subdir)

  begin
    SafeImage.thumbnail(input: JPG, output: File.join(subdir, "out.jpg"), width: 10, height: 10)
    abort "thumbnail accepted symlink parent output"
  rescue SafeImage::UnsafePathError
  end
end

puts "OK symlink path safety"

# Relative input paths are expanded to absolute before processing, so the
# ImageMagick-backed helpers accept them just like the rest of the public API.
Dir.chdir(FIXTURES) do
  abort "orientation rejected a relative path" unless SafeImage.orientation("huge.jpg").is_a?(Integer)
  abort "frame_count rejected a relative path" unless SafeImage.frame_count("huge.jpg", max_pixels: 100_000_000).is_a?(Integer)
  abort "animated? rejected a relative path" unless SafeImage.animated?("huge.jpg", max_pixels: 100_000_000) == false
end

puts "OK relative path inputs"
