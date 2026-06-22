# frozen_string_literal: true

require_relative "base"

module SafeImage
  module OperationBackends
    # ImageMagick operation orchestration. Inputs/outputs still pass the shared
    # path safety checks before the lower backend builds argv arrays with coder:
    # prefixes and the restrictive policy.xml.
    class ImageMagick < Base
      def resize(input:, output:, width:, height:, quality:, optimize:, max_pixels:, chroma_subsampling: nil)
        input, output = input_output!(input, output)
        probe = operation_probe(input, max_pixels: resolved_max_pixels(max_pixels))
        output = safe_output!(output)
        info =
          ImageMagickBackend.thumbnail(
            input: probe.input,
            output: output,
            width: width,
            height: height,
            format: Formats.extension(output),
            quality: quality
          )
        optimize_output(output, quality) if optimize
        result_from_info(probe.input, output, info, :imagemagick, tier: :resize)
      end

      def crop(input:, output:, width:, height:, quality:, optimize:, max_pixels:, chroma_subsampling: nil)
        input, output = input_output!(input, output)
        probe = operation_probe(input, max_pixels: resolved_max_pixels(max_pixels))
        output = safe_output!(output)
        info =
          ImageMagickBackend.resize_like(
            input: probe.input,
            output: output,
            width: width,
            height: height,
            format: Formats.extension(output),
            quality: quality,
            crop: :north
          )
        optimize_output(output, quality) if optimize
        result_from_info(probe.input, output, info, :imagemagick, tier: :crop)
      end

      def downsize(input:, output:, dimensions:, optimize:, max_pixels:, quality: nil, chroma_subsampling: nil)
        input, output = input_output!(input, output)
        probe = operation_probe(input, max_pixels: resolved_max_pixels(max_pixels))
        output = safe_output!(output)
        info =
          ImageMagickBackend.downsize(
            input: probe.input,
            output: output,
            dimensions: dimensions,
            format: Formats.extension(output)
          )
        optimize_output(output, nil) if optimize
        result_from_info(probe.input, output, info, :imagemagick, tier: :downsize)
      end

      def convert(input:, output:, format:, quality:, optimize:, max_pixels:, chroma_subsampling: nil)
        input, output = input_output!(input, output)
        probe = operation_probe(input, max_pixels: resolved_max_pixels(max_pixels))
        normalized_format = Formats.normalize(format)
        info = ImageMagickBackend.convert(input: probe.input, output: output, format: format, quality: quality)
        optimize_output(output, normalized_format == "jpg" ? quality : nil) if optimize
        result_from_info(probe.input, output, info, :imagemagick, tier: :convert)
      end

      def fix_orientation(input:, output:, max_pixels:, quality: nil)
        input, output = input_output!(input, output)
        probe = operation_probe(input, max_pixels: resolved_max_pixels(max_pixels))
        info = ImageMagickBackend.fix_orientation(input: probe.input, output: output)
        result_from_info(probe.input, output, info, :imagemagick, tier: :fix_orientation)
      end

      def convert_favicon_to_png(input:, output:, optimize:, max_pixels: nil)
        input, output = input_output!(input, output)
        info = ImageMagickBackend.convert_ico_to_png(input: Pathname.new(input).expand_path.to_s, output: output)
        optimize_output(output, nil) if optimize
        result_from_info(input, output, info, :imagemagick, tier: :convert_favicon)
      end

      def letter_avatar(output:, size:, background_rgb:, letter:, pointsize:, font:)
        output = safe_output!(output)
        request = {
          output: output,
          size: size,
          background_rgb: background_rgb,
          letter: letter,
          pointsize: pointsize,
          font: font
        }
        result_from_info(
          "generated",
          output,
          ImageMagickBackend.letter_avatar(**request),
          :imagemagick,
          tier: :letter_avatar
        )
      end

      private

      def operation_probe(path, max_pixels:)
        path = Pathname.new(path).expand_path.to_s
        info = ImageMagickBackend.probe(path, max_pixels: max_pixels)
        Result.metadata(
          input: path,
          input_format: info.fetch(:input_format),
          width: info.fetch(:width),
          height: info.fetch(:height),
          backend: :imagemagick,
          duration_ms: info.fetch(:duration_ms)
        )
      end

      def backend_frame_count(path, max_pixels:)
        ImageMagickBackend.frame_count(path, max_pixels: max_pixels)
      end
    end
  end
end
