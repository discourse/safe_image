# frozen_string_literal: true

require_relative "test_helper"

module SafeImage
  # Golden expectations for the public processing operations across both
  # backends. Dimensions are pinned so behavioural drift shows up as a
  # failure rather than a silent change.
  class OperationsTest < TestCase
    def test_probe_reports_format_and_dimensions
      probe = SafeImage.probe(JPG, max_pixels: JPG_PIXELS)
      assert_equal [8900, 8900], [probe.width, probe.height]
      refute_empty probe.input_format.to_s
    end

    def test_thumbnail_with_vips_backend
      result = SafeImage.thumbnail(
        input: JPG, output: tmp_path("thumb.jpg"),
        width: 600, height: 400, backend: :vips, optimize: true, max_pixels: JPG_PIXELS
      )
      assert_result result, width: 600, height: 400, format: "jpg"
    end

    def test_thumbnail_with_imagemagick_backend
      result = SafeImage.thumbnail(
        input: JPG, output: tmp_path("thumb.jpg"),
        width: 600, height: 400, backend: :imagemagick, optimize: true, max_pixels: JPG_PIXELS
      )
      assert_result result, width: 600, height: 400, format: "jpg"
    end

    def test_thumbnail_of_animated_webp
      result = SafeImage.thumbnail(
        input: WEBP, output: tmp_path("webp.jpg"),
        width: 120, height: 120, backend: :vips, optimize: true, max_pixels: PNG_PIXELS
      )
      assert_result result, width: 120, height: 120
    end

    def test_crop_with_imagemagick_backend
      result = SafeImage.crop(JPG, tmp_path("crop.jpg"), 400, 400, backend: :imagemagick, max_pixels: JPG_PIXELS)
      assert_result result, width: 400, height: 400, format: "jpg"
    end

    def test_crop_with_vips_backend
      result = SafeImage.crop(JPG, tmp_path("crop.jpg"), 400, 400, backend: :vips, max_pixels: JPG_PIXELS)
      assert_result result, width: 400, height: 400, format: "jpg"
    end

    def test_downsize_by_percentage_with_imagemagick_backend
      result = SafeImage.downsize(PNG, tmp_path("down.png"), "50%", backend: :imagemagick, max_pixels: PNG_PIXELS)
      assert_result result, width: 1016, height: 656, format: "png"
    end

    def test_downsize_by_percentage_with_vips_backend
      result = SafeImage.downsize(PNG, tmp_path("down.png"), "50%", backend: :vips, max_pixels: PNG_PIXELS)
      assert_result result, width: 1016, height: 656, format: "png"
    end

    def test_downsize_to_bounding_box
      result = SafeImage.downsize(PNG, tmp_path("down.png"), "100x100>", backend: :vips, max_pixels: PNG_PIXELS)
      assert_result result, width: 100, height: 65, format: "png"
    end

    def test_downsize_to_target_pixel_count
      result = SafeImage.downsize(PNG, tmp_path("down.png"), "400000@", backend: :vips, max_pixels: PNG_PIXELS)
      assert_result result, width: 787, height: 508, format: "png"
    end

    def test_convert_png_to_jpeg
      result = SafeImage.convert(PNG, tmp_path("png.jpg"), format: "jpg", quality: 85, max_pixels: PNG_PIXELS)
      assert_result result, width: 2032, height: 1312, format: "jpg"
    end

    def test_convert_heic_to_jpeg
      result = heic_or_skip do
        SafeImage.convert(HEIC, tmp_path("heic.jpg"), format: "jpg", quality: 85, max_pixels: PNG_PIXELS)
      end
      assert_result result, width: 846, height: 1129, format: "jpg"
    end

    def test_convert_favicon_to_png
      result = SafeImage.convert_favicon_to_png(ICO, tmp_path("ico.png"))
      assert_result result, width: 1, height: 1, format: "png"
    end

    def test_letter_avatar
      result = SafeImage.letter_avatar(
        output: tmp_path("letter.png"),
        size: 360, background_rgb: [1, 2, 3], letter: "S", font: "Adwaita-Sans"
      )
      assert_result result, width: 360, height: 360, format: "png"
    end
  end
end
