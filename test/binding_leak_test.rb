# frozen_string_literal: true

require_relative "test_helper"

module SafeImage
  # The vips backend now lives in a helper process; this test hammers a
  # representative mix of operations and asserts the Ruby parent does not grow
  # monotonically while staging helper requests and parsing responses.
  class BindingLeakTest < TestCase
    ITERATIONS = 50
    ALLOWED_GROWTH_KB = 30_000

    def test_repeated_operations_do_not_leak
      skip "requires /proc" unless File.readable?("/proc/self/status")

      # Warm caches, lazy init and allocator pools.
      5.times { exercise }
      GC.start
      before = rss_kb

      ITERATIONS.times { exercise }
      GC.start
      after = rss_kb

      assert_operator after - before,
                      :<,
                      ALLOWED_GROWTH_KB,
                      "RSS grew #{after - before}KB over #{ITERATIONS} iterations; helper request handling may be leaking"
    end

    private

    # Touches the helper-backed paths: loaders, metadata reads, stats, text,
    # thumbnailing and the raw-memory PNG encoder.
    def exercise
      SafeImage.size(GIF, max_pixels: PNG_PIXELS)
      SafeImage.dominant_color(GIF, max_pixels: PNG_PIXELS)
      SafeImage.thumbnail(
        input: GIF,
        output: tmp_path("leak.jpg"),
        width: 64,
        height: 64,
        optimize: false,
        max_pixels: PNG_PIXELS
      )
      SafeImage.letter_avatar(output: tmp_path("leak.png"), size: 64, background_rgb: [1, 2, 3], letter: "S")
      Native.png_from_rgba("\xFF\x00\x00\xFF".b * 64, 8, 8, tmp_path("leak-rgba.png"))
    end

    def rss_kb
      File.read("/proc/self/status")[/VmRSS:\s+(\d+)/, 1].to_i
    end
  end
end
