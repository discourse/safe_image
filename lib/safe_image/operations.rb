# frozen_string_literal: true

module SafeImage
  # Thin public-operation facade. Path validation, backend-specific pipelines,
  # post-processing and result tiers live in OperationBackends::* so this file is
  # just the stable API-shaped dispatch layer.
  module Operations
    module_function

    def backend(config: SafeImage.config)
      OperationBackends.for(config)
    end

    def resize(
      input:,
      output:,
      width:,
      height:,
      quality: nil,
      optimize: true,
      max_pixels: nil,
      chroma_subsampling: :auto,
      config: SafeImage.config
    )
      backend(config: config).resize(
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
      chroma_subsampling: :auto,
      config: SafeImage.config
    )
      backend(config: config).crop(
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
      chroma_subsampling: :auto,
      config: SafeImage.config
    )
      backend(config: config).downsize(
        input: input,
        output: output,
        dimensions: dimensions,
        optimize: optimize,
        max_pixels: max_pixels,
        quality: quality,
        chroma_subsampling: chroma_subsampling
      )
    end

    def convert(
      input:,
      output:,
      format:,
      quality: nil,
      optimize: true,
      max_pixels: nil,
      chroma_subsampling: :auto,
      config: SafeImage.config
    )
      backend(config: config).convert(
        input: input,
        output: output,
        format: format,
        quality: quality,
        optimize: optimize,
        max_pixels: max_pixels,
        chroma_subsampling: chroma_subsampling
      )
    end

    def fix_orientation(input:, output:, max_pixels: nil, quality: nil, config: SafeImage.config)
      backend(config: config).fix_orientation(input: input, output: output, max_pixels: max_pixels, quality: quality)
    end

    def convert_favicon_to_png(input:, output:, optimize: true, max_pixels: nil, config: SafeImage.config)
      backend(config: config).convert_favicon_to_png(
        input: input,
        output: output,
        optimize: optimize,
        max_pixels: max_pixels
      )
    end

    def frame_count(path, max_pixels: nil, config: SafeImage.config)
      backend(config: config).frame_count(path, max_pixels: max_pixels)
    end

    def animated?(path, max_pixels: nil, config: SafeImage.config)
      frame_count(path, max_pixels: max_pixels, config: config).to_i > 1
    end

    def letter_avatar(
      output:,
      size:,
      background_rgb:,
      letter:,
      pointsize: 280,
      font: "DejaVu-Sans",
      config: SafeImage.config
    )
      backend(config: config).letter_avatar(
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
