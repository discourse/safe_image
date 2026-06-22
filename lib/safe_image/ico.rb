# frozen_string_literal: true

require "tempfile"

module SafeImage
  # Pure-Ruby ICO container support, in the spirit of the SVG metadata path:
  # the directory and legacy DIB payloads are parsed in memory-safe Ruby with
  # explicit bounds checks, and pixel encoding is delegated to the hardened
  # native libvips helpers. ImageMagick is never involved.
  #
  # PNG payloads (every modern favicon) are re-encoded through the native
  # libvips PNG path rather than copied through verbatim, so output never
  # contains attacker-controlled bytes. DIB payloads support the formats that
  # exist in the wild: uncompressed BI_RGB at 1/4/8/24/32 bits per pixel plus
  # the 1-bit AND transparency mask.
  module Ico
    module_function

    MAX_BYTES = 5 * 1024 * 1024
    MAX_ENTRIES = 256
    # The directory caps entry dimensions at 256 (a stored 0 means 256); a DIB
    # header claiming more is lying about the payload.
    MAX_DIB_DIMENSION = 256
    PNG_MAGIC = "\x89PNG\r\n\x1a\n".b.freeze
    BI_RGB = 0

    Entry = Data.define(:width, :height, :bpp, :offset, :size, :png)

    def probe(path, max_pixels: nil)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      data, entries = parse(path)
      entry = largest(entries)
      width, height = entry_dimensions(data, entry)
      validate_pixels!(width, height, max_pixels)
      {
        width: width,
        height: height,
        frames: entries.length,
        duration_ms: (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000
      }
    end

    def frame_count(path, max_pixels: nil)
      probe(path, max_pixels: max_pixels).fetch(:frames)
    end

    # Extracts the largest icon and writes it as PNG. Returns an info hash in
    # shape Operations.result_from_info expects.
    def convert_to_png(input, output, max_pixels: nil)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      data, entries = parse(input)
      entry = largest(entries)
      output = PathSafety.ensure_safe_output_path!(output).to_s

      width = height = nil
      StagedOutput.replace(output, suffix: ".safe-image.png") do |tmp_path|
        if entry.png
          # Enforce the pixel cap from the IHDR dimensions before the payload
          # reaches a decoder.
          validate_pixels!(*entry_dimensions(data, entry), max_pixels)
          payload = data.byteslice(entry.offset, entry.size)
          Tempfile.create(%w[safe-image-ico .png]) do |tmp|
            tmp.binmode
            tmp.write(payload)
            tmp.close
            # Sanitizing no-op resize: validates the PNG bytes, enforces the
            # pixel cap and strips metadata on the way through libvips.
            info = Native.resize(tmp.path, tmp_path.to_s, 1.0, "png", 100, max_pixels)
            width = info.fetch(:width)
            height = info.fetch(:height)
          end
        else
          rgba, width, height = decode_rgba(data, entry)
          validate_pixels!(width, height, max_pixels)
          Native.png_from_rgba(rgba, width, height, tmp_path.to_s)
        end
      end

      {
        input_format: "ico",
        output_format: "png",
        width: width,
        height: height,
        duration_ms: (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000
      }
    end

    # -- container parsing ---------------------------------------------------

    def parse(path)
      path = PathSafety.ensure_regular_file!(path).to_s
      size = File.size(path)
      raise LimitError, "ico file has #{size} bytes, exceeds #{MAX_BYTES}" if size > MAX_BYTES
      raise InvalidImageError, "ico file is truncated" if size < 6 + 16

      data = File.binread(path)
      reserved, type, count = data.unpack("vvv")
      raise InvalidImageError, "not an ico file" unless reserved == 0 && type == 1
      raise InvalidImageError, "ico directory is empty" if count.zero?
      raise LimitError, "ico has #{count} entries, exceeds #{MAX_ENTRIES}" if count > MAX_ENTRIES

      entries =
        count.times.map do |index|
          dir_offset = 6 + index * 16
          raise InvalidImageError, "ico directory is truncated" if data.bytesize < dir_offset + 16

          w8, h8, _colors, _reserved, _planes, bpp, bytes, img_offset =
            data.byteslice(dir_offset, 16).unpack("CCCCvvVV")
          if bytes < 16 || img_offset < 6 + count * 16 || img_offset + bytes > data.bytesize
            raise InvalidImageError, "ico entry #{index} is out of bounds"
          end

          Entry.new(
            width: w8.zero? ? 256 : w8,
            height: h8.zero? ? 256 : h8,
            bpp: bpp,
            offset: img_offset,
            size: bytes,
            png: data.byteslice(img_offset, 8) == PNG_MAGIC
          )
        end

      [data, entries]
    end

    def largest(entries)
      entries.max_by { |entry| [entry.width * entry.height, entry.bpp] }
    end

    # PNG payloads carry their real dimensions in the IHDR chunk; the
    # one-byte directory fields saturate at 256.
    def entry_dimensions(data, entry)
      return entry.width, entry.height unless entry.png
      raise InvalidImageError, "png payload is truncated" if entry.size < 24
      data.byteslice(entry.offset + 16, 8).unpack("NN")
    end

    def validate_pixels!(width, height, max_pixels)
      raise InvalidImageError, "ico has invalid dimensions" if width.nil? || height.nil? || width < 1 || height < 1
      limit = max_pixels ? Integer(max_pixels) : DEFAULT_MAX_PIXELS
      pixels = width * height
      raise LimitError, "image has #{pixels} pixels, exceeds #{limit}" if pixels > limit
    end

    # -- DIB payload decoding ------------------------------------------------

    # Decodes a BITMAPINFOHEADER payload (XOR bitmap + 1-bit AND mask) into a
    # top-down RGBA buffer. Returns [rgba_bytes, width, height].
    def decode_rgba(data, entry)
      payload = data.byteslice(entry.offset, entry.size)
      raise InvalidImageError, "dib payload is truncated" if payload.bytesize < 40

      header_size, width, height2, _planes, bpp, compression, _img_size, _xppm, _yppm, colors_used =
        payload.unpack("Vl<l<vvVVl<l<V")
      raise InvalidImageError, "unsupported dib header (size #{header_size})" if header_size != 40
      raise InvalidImageError, "unsupported dib compression #{compression}" unless compression == BI_RGB
      raise InvalidImageError, "unsupported dib bit depth #{bpp}" if [1, 4, 8, 24, 32].none? { |bits| bits == bpp }

      top_down = height2.negative?
      height = height2.abs / 2
      if width < 1 || height < 1 || width > MAX_DIB_DIMENSION || height > MAX_DIB_DIMENSION || height2.abs.odd?
        raise InvalidImageError, "dib dimensions are invalid (#{width}x#{height2})"
      end

      palette = []
      palette_offset = header_size
      if bpp <= 8
        palette_count = colors_used.zero? ? (1 << bpp) : colors_used
        raise InvalidImageError, "dib palette is invalid" if palette_count > 1 << bpp
        raise InvalidImageError, "dib palette is truncated" if payload.bytesize < palette_offset + palette_count * 4
        palette =
          payload
            .byteslice(palette_offset, palette_count * 4)
            .unpack("C*")
            .each_slice(4)
            .map { |b, g, r, _x| [r, g, b] }
        palette_offset += palette_count * 4
      end

      xor_stride = ((width * bpp + 31) / 32) * 4
      and_stride = ((width + 31) / 32) * 4
      xor_bytes = xor_stride * height
      and_bytes = and_stride * height
      if payload.bytesize < palette_offset + xor_bytes + and_bytes
        raise InvalidImageError, "dib pixel data is truncated"
      end

      xor_data = payload.byteslice(palette_offset, xor_bytes)
      and_data = payload.byteslice(palette_offset + xor_bytes, and_bytes)

      rgba =
        if bpp == 32
          decode_32bpp(xor_data, and_data, width, height, and_stride, top_down)
        else
          decode_low_bpp(xor_data, and_data, palette, width, height, bpp, xor_stride, and_stride, top_down)
        end

      [rgba, width, height]
    end

    # 32bpp is the format every real-world DIB favicon uses, so it gets a
    # bulk path: reorder rows with byteslice, then swap BGRA to RGBA in one
    # unpack/map!/pack pass. Reading big-endian makes the swap a single
    # rotate-right-by-8.
    def decode_32bpp(xor_data, and_data, width, height, and_stride, top_down)
      stride = width * 4
      xor_data = (0...height).map { |y| xor_data.byteslice((height - 1 - y) * stride, stride) }.join unless top_down
      pixels = xor_data.unpack("N*")

      if alpha_all_zero?(xor_data)
        # Pre-alpha icons leave every alpha byte zero and rely on the 1-bit
        # AND mask (the Windows convention). A mask with no set bits means
        # fully opaque, which bulk-converts; otherwise the rotated pixel
        # keeps alpha 0 and only unmasked pixels need the opaque byte set.
        if and_data.count("\x00") == and_data.bytesize
          pixels.map! { |x| (x >> 8) | 0xFF000000 }
        else
          i = 0
          height.times do |out_y|
            mask_offset = (top_down ? out_y : height - 1 - out_y) * and_stride
            width.times do |x|
              value = pixels[i] >> 8
              value |= 0xFF000000 if (and_data.getbyte(mask_offset + (x >> 3)) & (0x80 >> (x & 7))).zero?
              pixels[i] = value
              i += 1
            end
          end
        end
      else
        pixels.map! { |x| (x >> 8) | ((x & 0xFF) << 24) }
      end

      pixels.pack("V*")
    end

    def decode_low_bpp(xor_data, and_data, palette, width, height, bpp, xor_stride, and_stride, top_down)
      # Precomputed 4-byte RGBA chunks per palette entry (opaque and masked
      # variants) turn the pixel body into a single string append.
      if bpp <= 8
        opaque = palette.map { |r, g, b| [r, g, b, 255].pack("C4") }
        transparent = palette.map { |r, g, b| [r, g, b, 0].pack("C4") }
      end

      rgba = String.new(capacity: width * height * 4, encoding: Encoding::BINARY)
      height.times do |out_y|
        src_y = top_down ? out_y : height - 1 - out_y
        xor_row = xor_data.byteslice(src_y * xor_stride, xor_stride)
        and_row = and_data.byteslice(src_y * and_stride, and_stride)
        width.times do |x|
          masked = (and_row.getbyte(x >> 3) & (0x80 >> (x & 7))).positive?
          if bpp == 24
            b = xor_row.getbyte(x * 3)
            g = xor_row.getbyte(x * 3 + 1)
            r = xor_row.getbyte(x * 3 + 2)
            rgba << r << g << b << (masked ? 0 : 255)
            next
          end

          index =
            case bpp
            when 8
              xor_row.getbyte(x)
            when 4
              (
                byte = xor_row.getbyte(x >> 1)
                x.even? ? byte >> 4 : byte & 0x0F
              )
            else
              (xor_row.getbyte(x >> 3) >> (7 - (x & 7))) & 1
            end
          rgba << (masked ? transparent : opaque).fetch(index) do
            raise InvalidImageError, "dib palette index #{index} is out of range"
          end
        end
      end
      rgba
    end

    # Possessive quantifier: the regex engine scans 4-byte groups in C with
    # no backtracking, so the worst case (an all-zero legacy icon) stays
    # sub-millisecond where a getbyte loop takes milliseconds.
    ALPHA_ALL_ZERO = /\A(?:.{3}\x00)*+\z/mn

    def alpha_all_zero?(xor_data)
      xor_data.match?(ALPHA_ALL_ZERO)
    end
  end
end
