# frozen_string_literal: true

require_relative "test_helper"

module SafeImage
  # The libvips path caps decoded pixels even when the caller passes no
  # max_pixels, so a decompression bomb is rejected by default. Callers that
  # legitimately need larger images opt in with an explicit max_pixels.
  class PixelLimitTest < TestCase
    def test_default_cap_rejects_decompression_bomb
      assert_raises(LimitError) do
        SafeImage.thumbnail(input: bomb, output: tmp_path("thumb.png"), width: 32, height: 32, optimize: false)
      end
    end

    def test_explicit_max_pixels_overrides_the_default_cap
      result =
        SafeImage.thumbnail(
          input: bomb,
          output: tmp_path("ok.png"),
          width: 32,
          height: 32,
          optimize: false,
          max_pixels: 200_000_000
        )
      assert_result result, width: 32, height: 32
    end

    private

    # 12000x12000 = 144MP, above the 128MP default cap.
    def bomb
      @bomb ||= tmp_path("bomb.png").tap { |path| PngFactory.write_solid_png(path, 12_000, 12_000) }
    end
  end
end
