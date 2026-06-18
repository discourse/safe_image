# frozen_string_literal: true

require_relative "test_helper"

module SafeImage
  class IcoTest < TestCase
    FAVICON = File.join(FIXTURES, "favicon.ico") # 256/48/32/16 entries, 32bpp DIB payloads

    def test_probe_reports_largest_entry_and_count
      result = SafeImage.probe(FAVICON)

      assert_equal "ico", result.input_format
      assert_equal [256, 256], [result.width, result.height]
      assert_equal "ico-metadata", result.backend
      assert_equal 4, SafeImage.frame_count(FAVICON)
      assert_equal :ico, SafeImage.type(FAVICON)
    end

    def test_convert_favicon_extracts_largest_entry
      result = SafeImage.convert_favicon_to_png(input: FAVICON, output: tmp_path("favicon.png"))

      assert_result result, width: 256, height: 256, format: "png"
      assert_equal :png, SafeImage.type(tmp_path("favicon.png"))
    end

    def test_convert_favicon_with_png_payload
      small = tmp_path("payload.png")
      SafeImage.thumbnail(input: PNG, output: small, width: 64, height: 64, max_pixels: PNG_PIXELS)
      ico = write_ico("png_payload.ico", [{ width: 64, height: 64, payload: File.binread(small) }])

      assert_equal [64, 64], SafeImage.size(ico)
      result = SafeImage.convert_favicon_to_png(input: ico, output: tmp_path("out.png"))
      assert_result result, width: 64, height: 64, format: "png"
    end

    def test_decodes_one_bit_palette_payload
      ico = write_ico("tiny.ico", [{ width: 2, height: 2, bpp: 1, payload: one_bit_dib_payload }])
      data, entries = Ico.parse(ico)
      rgba, width, height = Ico.decode_rgba(data, entries.first)

      assert_equal [2, 2], [width, height]
      assert_equal [255, 0, 0, 255, 0, 0, 0, 0, 0, 0, 0, 255, 255, 0, 0, 255], rgba.bytes
    end

    def test_decodes_legacy_zero_alpha_payload_with_mask
      # 2x2 32bpp, all alpha bytes zero (pre-alpha icon): TL red, TR green
      # (masked transparent), BL blue, BR white. Rows stored bottom-up.
      xor = [
        [255, 0, 0, 0],
        [255, 255, 255, 0], # bottom row: blue, white (BGRA)
        [0, 0, 255, 0],
        [0, 255, 0, 0] # top row: red, green
      ].flatten.pack("C*")
      and_mask = "\x00\x00\x00\x00".b + "\x40\x00\x00\x00".b
      header = [40, 2, 4, 1, 32, 0, 0, 0, 0, 0, 0].pack("Vl<l<vvVVl<l<VV")
      ico = write_ico("legacy.ico", [{ width: 2, height: 2, payload: header + xor + and_mask }])

      data, entries = Ico.parse(ico)
      rgba, = Ico.decode_rgba(data, entries.first)

      assert_equal [255, 0, 0, 255, 0, 255, 0, 0, 0, 0, 255, 255, 255, 255, 255, 255], rgba.bytes
    end

    def test_decodes_legacy_zero_alpha_payload_with_opaque_mask
      xor = [[255, 0, 0, 0], [0, 0, 255, 0]].flatten.pack("C*")
      and_mask = "\x00\x00\x00\x00".b
      header = [40, 2, 2, 1, 32, 0, 0, 0, 0, 0, 0].pack("Vl<l<vvVVl<l<VV")
      ico = write_ico("opaque.ico", [{ width: 2, height: 1, payload: header + xor + and_mask }])

      data, entries = Ico.parse(ico)
      rgba, = Ico.decode_rgba(data, entries.first)

      assert_equal [0, 0, 255, 255, 255, 0, 0, 255], rgba.bytes
    end

    def test_dominant_color_weights_by_alpha
      ico = write_ico("tiny.ico", [{ width: 2, height: 2, bpp: 1, payload: one_bit_dib_payload }])

      # red, transparent black, black, red: E[r*a]/E[a] = 170
      assert_equal "AA0000", SafeImage.dominant_color(ico)
    end

    def test_png_payload_pixel_cap_is_enforced_without_decoding
      fake_png = +PNG_MAGIC
      fake_png << [13].pack("N") << "IHDR" << [100_000, 100_000].pack("NN") << "\0" * 5
      ico = write_ico("bomb.ico", [{ width: 256, height: 256, payload: fake_png }])

      assert_raises(LimitError) { SafeImage.probe(ico) }
      assert_raises(LimitError) { SafeImage.convert_favicon_to_png(input: ico, output: tmp_path("bomb.png")) }
    end

    def test_rejects_garbage
      assert_raises(InvalidImageError) { SafeImage.probe(write_tmp("garbage.ico", "not an ico")) }
    end

    def test_rejects_out_of_bounds_entry
      ico = [0, 1, 1].pack("vvv") + [16, 16, 0, 0, 1, 32, 999_999, 22].pack("CCCCvvVV") + "x"

      assert_raises(InvalidImageError) { SafeImage.probe(write_tmp("oob.ico", ico)) }
    end

    def test_rejects_unsupported_dib_compression
      payload = [40, 2, 4, 1, 32, 3, 0, 0, 0, 0, 0].pack("Vl<l<vvVVl<l<VV") + "\0" * 64
      ico = write_ico("rle.ico", [{ width: 2, height: 2, payload: payload }])

      assert_raises(InvalidImageError) { SafeImage.convert_favicon_to_png(input: ico, output: tmp_path("rle.png")) }
    end

    def test_rejects_oversized_files
      original = Ico::MAX_BYTES
      ico = write_tmp("big.ico", "\0" * 32)
      Ico.send(:remove_const, :MAX_BYTES)
      Ico.const_set(:MAX_BYTES, 16)

      assert_raises(LimitError) { SafeImage.probe(ico) }
    ensure
      Ico.send(:remove_const, :MAX_BYTES)
      Ico.const_set(:MAX_BYTES, original)
    end

    private

    PNG_MAGIC = "\x89PNG\r\n\x1a\n".b

    def write_ico(name, entries)
      count = entries.length
      ico = +[0, 1, count].pack("vvv")
      offset = 6 + 16 * count
      entries.each do |entry|
        width = entry[:width] >= 256 ? 0 : entry[:width]
        height = entry[:height] >= 256 ? 0 : entry[:height]
        ico << [width, height, 0, 0, 1, entry.fetch(:bpp, 32), entry[:payload].bytesize, offset].pack("CCCCvvVV")
        offset += entry[:payload].bytesize
      end
      entries.each { |entry| ico << entry[:payload] }
      write_tmp(name, ico)
    end

    # 2x2, 1bpp: palette [black, red]; pixels TL=red TR=black BL=black BR=red;
    # AND mask marks TR transparent. Rows are stored bottom-up, stride 4.
    def one_bit_dib_payload
      header = [40, 2, 4, 1, 1, 0, 0, 0, 0, 2, 0].pack("Vl<l<vvVVl<l<VV")
      palette = "\x00\x00\x00\x00".b + "\x00\x00\xFF\x00".b
      xor = "\x40\x00\x00\x00".b + "\x80\x00\x00\x00".b
      and_mask = "\x00\x00\x00\x00".b + "\x40\x00\x00\x00".b
      header + palette + xor + and_mask
    end
  end
end
