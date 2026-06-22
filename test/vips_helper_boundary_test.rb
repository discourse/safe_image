# frozen_string_literal: true

require_relative "test_helper"

module SafeImage
  class VipsHelperBoundaryTest < TestCase
    def test_vips_backend_does_not_load_libvips_into_the_ruby_process
      skip "requires /proc maps" unless File.readable?("/proc/self/maps")

      SafeImage.size(PNG, max_pixels: PNG_PIXELS)

      refute_includes File.read("/proc/self/maps"), "libvips", "libvips must stay isolated to the helper process"
    end
  end
end
