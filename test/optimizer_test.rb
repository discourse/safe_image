# frozen_string_literal: true

require_relative "test_helper"

module SafeImage
  class OptimizerTest < TestCase
    def test_optimize_image_runs_jpegoptim_on_jpeg
      jpg = tmp_path("converted.jpg")
      SafeImage.convert(PNG, jpg, format: "jpg", quality: 85, max_pixels: PNG_PIXELS)

      result = SafeImage.optimize_image!(jpg)
      assert_includes result.fetch(:tools), "jpegoptim"
    end

    def test_optimize_image_runs_oxipng_on_png
      png = tmp_path("down.png")
      SafeImage.downsize(PNG, png, "50%", max_pixels: PNG_PIXELS)

      result = SafeImage.optimize_image!(png, allow_lossy_png: true)
      assert_includes result.fetch(:tools), "oxipng"
    end
  end
end
