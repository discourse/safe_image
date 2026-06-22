# frozen_string_literal: true

require_relative "test_helper"

module SafeImage
  # The native helper wrapper validates arguments before spawning libvips.
  class NativeValidationTest < TestCase
    def test_thumbnail_rejects_zero_width
      assert_raises(ArgumentError) { Native.thumbnail(JPG, tmp_path("out.jpg"), 0, 10, "jpg", 85, nil) }
    end

    def test_thumbnail_rejects_quality_above_range
      assert_raises(ArgumentError) { Native.thumbnail(JPG, tmp_path("out.jpg"), 10, 10, "jpg", 101, nil) }
    end

    def test_thumbnail_rejects_non_positive_max_pixels
      assert_raises(ArgumentError) { Native.thumbnail(JPG, tmp_path("out.jpg"), 10, 10, "jpg", 85, 0) }
    end

    def test_resize_rejects_nan_scale
      assert_raises(ArgumentError) { Native.resize(JPG, tmp_path("out.jpg"), Float::NAN, "jpg", 85, nil) }
    end
  end
end
