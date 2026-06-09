# frozen_string_literal: true

require_relative "test_helper"

module SafeImage
  # The optional cjpegli encoder: explicit selection, automatic selection
  # for direct inputs, and fallbacks when it is missing or unsupported.
  class CjpegliTest < TestCase
    # Last-resort stub: Runner resolves binaries from a hardcoded
    # TRUSTED_PATH and ignores ENV["PATH"], so an installed cjpegli cannot
    # be made genuinely unavailable from a test.
    def test_forced_cjpegli_fails_when_unavailable
      JpegliBackend.stub(:available?, false) do
        assert_raises(UnsupportedFormatError) do
          SafeImage.convert(PNG, tmp_path("missing.jpg"), format: "jpg", encoder: :cjpegli)
        end
      end
    end

    def test_imagemagick_encoder_produces_jpeg
      out = tmp_path("fallback.jpg")
      SafeImage.convert(PNG, out, format: "jpg", encoder: :imagemagick, quality: 85, max_pixels: PNG_PIXELS)

      assert_jpeg_magic out
    end

    def test_convert_uses_cjpegli_when_forced
      require_cjpegli!
      out = tmp_path("converted.jpg")
      result = SafeImage.convert(PNG, out, format: "jpg", encoder: :cjpegli, quality: 85, max_pixels: PNG_PIXELS)

      assert_equal "cjpegli", result.backend
      assert_jpeg_magic out
      assert_equal :jpeg, SafeImage.type(out, max_pixels: PNG_PIXELS)
    end

    def test_auto_encoder_selects_cjpegli_for_direct_png_input
      require_cjpegli!
      result = SafeImage.convert(PNG, tmp_path("auto.jpg"), format: "jpg", quality: 85, max_pixels: PNG_PIXELS)

      assert_equal "cjpegli", result.backend
    end

    def test_auto_encoder_falls_back_for_heic_input
      require_cjpegli!
      result = heic_or_skip do
        SafeImage.convert(HEIC, tmp_path("heic.jpg"), format: "jpg", quality: 85, encoder: :auto, max_pixels: PNG_PIXELS)
      end

      refute_equal "cjpegli", result.backend, "auto should fall back for HEIC"
    end

    def test_forced_cjpegli_rejects_unsupported_heic_input
      require_cjpegli!
      assert_raises(UnsupportedFormatError) do
        SafeImage.convert(HEIC, tmp_path("bad-heic.jpg"), format: "jpg", encoder: :cjpegli, max_pixels: PNG_PIXELS)
      end
    end

    def test_forced_cjpegli_rejects_non_vips_backend
      require_cjpegli!
      assert_raises(ArgumentError) do
        SafeImage.thumbnail(
          input: JPG, output: tmp_path("bad-thumb.jpg"),
          width: 10, height: 10, backend: :imagemagick, encoder: :cjpegli, max_pixels: JPG_PIXELS
        )
      end
    end

    def test_thumbnail_with_cjpegli_encoder
      require_cjpegli!
      out = tmp_path("thumb.jpg")
      result = SafeImage.thumbnail(input: JPG, output: out, width: 320, height: 200, encoder: :cjpegli, max_pixels: JPG_PIXELS)

      assert_includes result.backend, "cjpegli"
      assert_result result, width: 320, height: 200
      assert_jpeg_magic out
    end

    def test_crop_with_cjpegli_encoder
      require_cjpegli!
      out = tmp_path("crop.jpg")
      result = SafeImage.crop(JPG, out, 200, 160, backend: :vips, encoder: :cjpegli, max_pixels: JPG_PIXELS)

      assert_includes result.backend, "cjpegli"
      assert_result result, width: 200, height: 160
      assert_jpeg_magic out
    end

    def test_downsize_with_cjpegli_encoder
      require_cjpegli!
      out = tmp_path("down.jpg")
      result = SafeImage.downsize(PNG, out, "320x200>", backend: :vips, encoder: :cjpegli, max_pixels: PNG_PIXELS)

      assert_includes result.backend, "cjpegli"
      assert_jpeg_magic out
    end

    def test_thumbnail_from_png_source_with_auto_chroma_subsampling
      require_cjpegli!
      out = tmp_path("thumb-from-png.jpg")
      result = SafeImage.thumbnail(
        input: PNG, output: out,
        width: 320, height: 200, encoder: :cjpegli, chroma_subsampling: :auto, max_pixels: PNG_PIXELS
      )

      assert_includes result.backend, "cjpegli"
      assert_jpeg_magic out
    end

    private

    def require_cjpegli!
      skip "cjpegli is not installed" unless JpegliBackend.available?
    end
  end
end
