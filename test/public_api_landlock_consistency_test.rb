# frozen_string_literal: true

require "fileutils"
require_relative "test_helper"

module SafeImage
  class PublicApiLandlockConsistencyTest < TestCase
    def test_safe_image_errors_preserve_class_across_sandbox_boundary
      each_landlock_mode do
        svg =
          write_tmp("masked.svg", '<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"><mask id="m"/></svg>')

        error = assert_raises(UnsupportedFormatError) { SafeImage.resize(svg, tmp_path("masked.png"), 5, 5) }
        assert_match(/unsupported input format/, error.message)
      end
    end

    def test_info_shape_preserves_symbols_across_sandbox_boundary
      each_landlock_mode do
        info = SafeImage.info(PNG, max_pixels: PNG_PIXELS)

        assert_instance_of Info, info
        assert_equal :png, info.type
        assert_equal [2032, 1312], info.size
      end
    end

    def test_existing_positional_output_is_writable_inside_sandbox
      skip "Landlock::SafeExec unavailable" unless SafeImage.sandbox_available?
      configure_safe_image(landlock: true)
      output = tmp_path("existing-output.png")
      FileUtils.cp(PNG, output)

      SafeImage.resize(PNG, output, 10, 10, max_pixels: PNG_PIXELS, optimize: false)

      assert_equal [10, 10], SafeImage.size(output, max_pixels: PNG_PIXELS)
    end

    private

    def each_landlock_mode
      [false, true].each do |landlock|
        next if landlock && !SafeImage.sandbox_available?
        configure_safe_image(landlock: landlock)
        yield
      end
    end
  end
end
