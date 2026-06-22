# frozen_string_literal: true

require "open3"
require_relative "test_helper"

module SafeImage
  # Hostile input is routine for this gem; libvips' GLib warnings stay inside
  # the helper subprocess' captured stderr. Failures still surface as exceptions,
  # but test output and production stderr are not littered by decoder warnings.
  class VipsLogSilenceTest < TestCase
    SCRIPT = <<~'RUBY'
      require "safe_image"
      begin
        SafeImage.configure!(backend: :vips, landlock: false)
        SafeImage.probe(ARGV[0])
      rescue SafeImage::InvalidImageError
        print "rejected"
      end
    RUBY

    def test_rejected_input_does_not_write_vips_warnings_to_stderr
      stdout, stderr, = run_probe

      assert_equal "rejected", stdout
      refute_match(/VIPS-WARNING/, stderr, "GLib warnings leaked to stderr")
    end

    private

    def run_probe
      fake = write_tmp("fake.png", "not a png")
      Open3.capture3(RbConfig.ruby, "-I", File.expand_path("../lib", __dir__), "-e", SCRIPT, fake)
    end
  end
end
