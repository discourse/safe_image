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
        transform_operations.thumbnail(
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
        )
      end

      def optimize(input:, output:, mode: :lossless, strip_metadata: true, quality: nil, strict: true)
        transform_operations.optimize(
          input: input,
          output: output,
          mode: mode,
          strip_metadata: strip_metadata,
          quality: quality,
          strict: strict
        )
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
        transform_operations.resize(
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
        transform_operations.crop(
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

      def downsize(
        input:,
        output:,
        dimensions:,
        optimize: true,
        max_pixels: nil,
        quality: QualityDefaults::JPEG,
        chroma_subsampling: :auto
      )
        transform_operations.downsize(
          input: input,
          output: output,
          dimensions: dimensions,
          optimize: optimize,
          max_pixels: max_pixels,
          quality: quality,
          chroma_subsampling: chroma_subsampling
        )
      end

      def convert(input:, output:, format:, quality: nil, optimize: true, max_pixels: nil, chroma_subsampling: :auto)
        transform_operations.convert(
          input: input,
          output: output,
          format: format,
          quality: quality,
          optimize: optimize,
          max_pixels: max_pixels,
          chroma_subsampling: chroma_subsampling
        )
      end

      def fix_orientation(input:, output:, max_pixels: nil, quality: nil)
        transform_operations.fix_orientation(input: input, output: output, max_pixels: max_pixels, quality: quality)
      end

      def convert_favicon_to_png(input:, output:, optimize: true, max_pixels: nil)
        transform_operations.convert_favicon_to_png(
          input: input,
          output: output,
          optimize: optimize,
          max_pixels: max_pixels
        )
      end

      def letter_avatar(output:, size:, background_rgb:, letter:, pointsize: 280, font: "DejaVu-Sans")
        transform_operations.letter_avatar(
          output: output,
          size: size,
          background_rgb: background_rgb,
          letter: letter,
          pointsize: pointsize,
          font: font
        )
      end

      private

      def transform_operations
        TransformOperations.new(config: SafeImage.config)
      end
    end
  end
end
