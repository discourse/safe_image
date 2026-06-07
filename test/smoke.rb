# frozen_string_literal: true

require "tmpdir"
require "pathname"
require_relative "../lib/discourse_image_processing"

input = ARGV[0] || "/home/agent/source/discourse/spec/fixtures/images/huge.jpg"
Dir.mktmpdir do |dir|
  out = File.join(dir, "thumb.jpg")
  probe = DiscourseImageProcessing.probe(input, max_pixels: 100_000_000)
  raise "bad probe #{probe.inspect}" unless probe.width.positive? && probe.height.positive?

  result = DiscourseImageProcessing.thumbnail(
    input: input,
    output: out,
    width: 600,
    height: 400,
    quality: 85,
    max_pixels: 100_000_000
  )
  raise "missing output" unless File.file?(out)
  raise "wrong dimensions #{result.inspect}" unless result.width == 600 && result.height == 400
  puts "OK #{probe.input_format} #{probe.width}x#{probe.height} -> #{result.output_format} #{result.width}x#{result.height} #{result.filesize} bytes"
end
