# frozen_string_literal: true

module SafeImage
  module API
    # Public image-producing operations. Every method requires explicit output
    # paths; callers own any file replacement outside this API.
    module Transform
      def thumbnail(
        input:,
        output:,
        width:,
        height:,
        format: nil,
        quality: QualityDefaults::JPEG,
        max_pixels: nil,
        optimize: false,
        optimize_mode: :lossless,
        chroma_subsampling: :auto
      )
        maybe_sandbox(
          :thumbnail,
          kwargs: {
            input: input,
            output: output,
            width: width,
            height: height,
            format: format,
            quality: quality,
            max_pixels: max_pixels,
            optimize: optimize,
            optimize_mode: optimize_mode,
            chroma_subsampling: chroma_subsampling
          }
        ) do
          Processor.new(max_pixels: resolved_max_pixels(max_pixels), chroma_subsampling: chroma_subsampling).thumbnail(
            input: input,
            output: output,
            width: width,
            height: height,
            format: format,
            quality: quality,
            optimize: optimize,
            optimize_mode: optimize_mode
          )
        end
      end

      def optimize(input:, output:, mode: :lossless, strip_metadata: true, quality: nil, strict: true)
        maybe_sandbox(
          :optimize,
          kwargs: {
            input: input,
            output: output,
            mode: mode,
            strip_metadata: strip_metadata,
            quality: quality,
            strict: strict
          }
        ) do
          Optimizer.optimize(
            input: input,
            output: output,
            mode: mode,
            strip_metadata: strip_metadata,
            quality: quality,
            strict: strict
          )
        end
      end

      def resize(
        input:,
        output:,
        width:,
        height:,
        quality: nil,
        optimize: true,
        max_pixels: nil,
        chroma_subsampling: :auto
      )
        maybe_sandbox(
          :resize,
          kwargs: {
            input: input,
            output: output,
            width: width,
            height: height,
            quality: quality,
            optimize: optimize,
            max_pixels: max_pixels,
            chroma_subsampling: chroma_subsampling
          }
        ) do
          Operations.resize(
            input: input,
            output: output,
            width: width,
            height: height,
            quality: quality,
            optimize: optimize,
            max_pixels: max_pixels,
            chroma_subsampling: chroma_subsampling
          )
        end
      end

      def crop(
        input:,
        output:,
        width:,
        height:,
        quality: nil,
        optimize: true,
        max_pixels: nil,
        chroma_subsampling: :auto
      )
        maybe_sandbox(
          :crop,
          kwargs: {
            input: input,
            output: output,
            width: width,
            height: height,
            quality: quality,
            optimize: optimize,
            max_pixels: max_pixels,
            chroma_subsampling: chroma_subsampling
          }
        ) do
          Operations.crop(
            input: input,
            output: output,
            width: width,
            height: height,
            quality: quality,
            optimize: optimize,
            max_pixels: max_pixels,
            chroma_subsampling: chroma_subsampling
          )
        end
      end

      def downsize(
        input:,
        output:,
        dimensions:,
        optimize: true,
        max_pixels: nil,
        quality: QualityDefaults::JPEG,
        chroma_subsampling: :auto
      )
        maybe_sandbox(
          :downsize,
          kwargs: {
            input: input,
            output: output,
            dimensions: dimensions,
            optimize: optimize,
            max_pixels: max_pixels,
            quality: quality,
            chroma_subsampling: chroma_subsampling
          }
        ) do
          Operations.downsize(
            input: input,
            output: output,
            dimensions: dimensions,
            optimize: optimize,
            max_pixels: max_pixels,
            quality: quality,
            chroma_subsampling: chroma_subsampling
          )
        end
      end

      def convert(input:, output:, format:, quality: nil, optimize: true, max_pixels: nil, chroma_subsampling: :auto)
        maybe_sandbox(
          :convert,
          kwargs: {
            input: input,
            output: output,
            format: format,
            quality: quality,
            optimize: optimize,
            max_pixels: max_pixels,
            chroma_subsampling: chroma_subsampling
          }
        ) do
          Operations.convert(
            input: input,
            output: output,
            format: format,
            quality: quality,
            optimize: optimize,
            max_pixels: max_pixels,
            chroma_subsampling: chroma_subsampling
          )
        end
      end

      def fix_orientation(input:, output:, max_pixels: nil, quality: nil)
        maybe_sandbox(
          :fix_orientation,
          kwargs: {
            input: input,
            output: output,
            max_pixels: max_pixels,
            quality: quality
          }
        ) { Operations.fix_orientation(input: input, output: output, max_pixels: max_pixels, quality: quality) }
      end

      def convert_favicon_to_png(input:, output:, optimize: true, max_pixels: nil)
        maybe_sandbox(
          :convert_favicon_to_png,
          kwargs: {
            input: input,
            output: output,
            optimize: optimize,
            max_pixels: max_pixels
          }
        ) do
          Operations.convert_favicon_to_png(input: input, output: output, optimize: optimize, max_pixels: max_pixels)
        end
      end

      def letter_avatar(output:, size:, background_rgb:, letter:, pointsize: 280, font: "DejaVu-Sans")
        maybe_sandbox(
          :letter_avatar,
          kwargs: {
            output: output,
            size: size,
            background_rgb: background_rgb,
            letter: letter,
            pointsize: pointsize,
            font: font
          }
        ) do
          Operations.letter_avatar(
            output: output,
            size: size,
            background_rgb: background_rgb,
            letter: letter,
            pointsize: pointsize,
            font: font
          )
        end
      end
    end
  end
end
