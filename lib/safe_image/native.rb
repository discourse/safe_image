# frozen_string_literal: true

require "tempfile"

module SafeImage
  # The libvips backend boundary. All libvips work is executed by the bundled
  # safe_image_vips_helper process; the Ruby process never dlopens libvips.
  # This module keeps the old Native call shape for the higher-level backend
  # code while doing only argument normalization and response shaping in Ruby.
  module Native
    class << self
      def available? = NativeHelper.available?

      def probe(path, max_pixels = nil)
        path = String(path)
        input_format!(path)
        info = NativeHelper.probe(path, checked_max_pixels(max_pixels))
        {
          format: info.fetch(:input_format),
          width: info.fetch(:width),
          height: info.fetch(:height),
          duration_ms: info.fetch(:duration_ms)
        }
      end

      def thumbnail(input, output, width, height, format, quality, max_pixels)
        width = Integer(width)
        height = Integer(height)
        quality = Integer(quality)
        raise ArgumentError, "width and height must be positive" if width <= 0 || height <= 0
        validate_quality!(quality)

        input = String(input)
        input_format!(input)
        NativeHelper.thumbnail(
          input,
          String(output),
          width,
          height,
          output_format!(format),
          quality,
          checked_max_pixels(max_pixels)
        )
      end

      def resize(input, output, scale, format, quality, max_pixels)
        scale = Float(scale)
        quality = Integer(quality)
        unless scale.finite? && scale.positive? && scale <= 100.0
          raise ArgumentError, "scale must be finite and in 0..100"
        end
        validate_quality!(quality)

        input = String(input)
        input_format!(input)
        NativeHelper.resize(
          input,
          String(output),
          scale,
          output_format!(format),
          quality,
          checked_max_pixels(max_pixels)
        )
      end

      def crop_north(input, output, width, height, format, quality, max_pixels)
        width = Integer(width)
        height = Integer(height)
        quality = Integer(quality)
        raise ArgumentError, "width and height must be positive" if width <= 0 || height <= 0
        validate_quality!(quality)

        input = String(input)
        input_format!(input)
        NativeHelper.crop_north(
          input,
          String(output),
          width,
          height,
          output_format!(format),
          quality,
          checked_max_pixels(max_pixels)
        )
      end

      def convert(input, output, format, quality, max_pixels)
        quality = Integer(quality)
        validate_quality!(quality)
        input = String(input)
        input_format!(input)
        NativeHelper.convert(input, String(output), output_format!(format), quality, checked_max_pixels(max_pixels))
      end

      def dominant_color(path, max_pixels)
        path = String(path)
        input_format!(path)
        hex = NativeHelper.dominant_color(path, checked_max_pixels(max_pixels))
        hex.scan(/../).map { |component| component.to_i(16) }
      end

      def pages(path, max_pixels)
        path = String(path)
        input_format!(path)
        NativeHelper.pages(path, checked_max_pixels(max_pixels))
      end

      def orientation(path, max_pixels)
        path = String(path)
        input_format!(path)
        NativeHelper.orientation(path, checked_max_pixels(max_pixels))
      end

      # Encodes a raw RGBA buffer (top-down rows) as PNG. Used by the pure-Ruby
      # ICO decoder; the raw bytes are staged to a tempfile and consumed by the
      # helper so libvips remains out of the Ruby process.
      def png_from_rgba(bytes, width, height, output)
        bytes = String(bytes)
        width = Integer(width)
        height = Integer(height)
        raise ArgumentError, "width and height must be positive" if width <= 0 || height <= 0
        raise LimitError, "rgba buffer dimensions exceed 4096x4096" if width > 4096 || height > 4096
        raise ArgumentError, "rgba buffer must be width*height*4 bytes" if bytes.bytesize != width * height * 4

        Tempfile.create(%w[safe-image-rgba .rgba], SafeImage.real_tmpdir, binmode: true) do |raw|
          raw.write(bytes)
          raw.close
          NativeHelper.png_from_rgba(raw.path, width, height, String(output))
        end
        true
      end

      # Renders a letter avatar through the helper. Markup has already been
      # escaped by VipsBackend; font tokens and font files come from its allowlist.
      def letter_avatar(output, size, red, green, blue, markup, font, fontfile)
        size = Integer(size)
        channels = [Integer(red), Integer(green), Integer(blue)]
        raise ArgumentError, "size must be 1..4096" unless (1..4096).cover?(size)
        unless channels.all? { |value| (0..255).cover?(value) }
          raise ArgumentError, "background channels must be 0..255"
        end

        NativeHelper.letter_avatar(
          String(output),
          size,
          channels[0],
          channels[1],
          channels[2],
          String(markup),
          String(font),
          String(fontfile)
        )
        true
      end

      private

      def input_format!(path)
        format = Formats.extension(path)
        raise UnsupportedFormatError, "unsupported input format" unless Formats.native_input?(format)

        format
      end

      def output_format!(format)
        normalized = Formats.normalize(String(format))
        canonical = Formats.native_canonical(normalized)
        unless Formats.native_output?(canonical) && canonical != "heic"
          raise UnsupportedFormatError, "unsupported output format"
        end

        canonical
      end

      def validate_quality!(quality)
        raise ArgumentError, "quality must be 1..100" unless (1..100).cover?(quality)
      end

      def checked_max_pixels(max_pixels)
        return nil if max_pixels.nil?

        max_pixels = Integer(max_pixels)
        raise ArgumentError, "max_pixels must be positive" if max_pixels <= 0

        max_pixels
      end
    end
  end
end
