# frozen_string_literal: true

module SafeImage
  # Single source of truth for Ruby-side format normalization and allowlists.
  # Native C helpers keep their own low-level allowlists, but Ruby orchestration
  # should ask this module before building backend-specific commands.
  module Formats
    module_function

    NATIVE_INPUTS = %w[jpg png gif webp heic heif avif jxl].freeze
    NATIVE_OUTPUTS = %w[jpg png gif webp avif jxl].freeze
    IMAGEMAGICK_INPUTS = (NATIVE_INPUTS + %w[ico]).freeze
    IMAGEMAGICK_OUTPUTS = (NATIVE_OUTPUTS + %w[ico]).freeze
    OPTIMIZABLE_OUTPUTS = %w[jpg png].freeze
    CJPEGLI_DIRECT_INPUTS = %w[png].freeze

    IMAGEMAGICK_DECODERS = {
      "jpg" => "jpeg",
      "png" => "png",
      "gif" => "gif",
      "webp" => "webp",
      "heic" => "heic",
      "heif" => "heic",
      "avif" => "heic",
      "ico" => "ico",
      "jxl" => "jxl"
    }.freeze

    IMAGEMAGICK_OUTPUT_CODERS = {
      "jpg" => "jpeg",
      "png" => "png",
      "gif" => "gif",
      "webp" => "webp",
      "avif" => "avif",
      "ico" => "ico",
      "jxl" => "jxl"
    }.freeze

    def normalize(format)
      format = format.to_s.delete_prefix(".").downcase
      format == "jpeg" ? "jpg" : format
    end

    def extension(path)
      normalize(File.extname(PathSafety.local_path(path)).delete_prefix("."))
    end

    def native_input?(format)
      NATIVE_INPUTS.include?(normalize(format))
    end

    def native_output?(format)
      NATIVE_OUTPUTS.include?(normalize(format))
    end

    def imagemagick_input?(format)
      IMAGEMAGICK_INPUTS.include?(normalize(format))
    end

    def imagemagick_output?(format)
      IMAGEMAGICK_OUTPUTS.include?(normalize(format))
    end

    def optimizable_output?(format)
      OPTIMIZABLE_OUTPUTS.include?(normalize(format))
    end

    def cjpegli_direct_input?(format)
      CJPEGLI_DIRECT_INPUTS.include?(normalize(format))
    end

    def imagemagick_decoder(format)
      normalized = normalize(format)
      IMAGEMAGICK_DECODERS.fetch(normalized) do
        raise UnsupportedFormatError, "unsupported ImageMagick input format: #{normalized.inspect}"
      end
    end

    def imagemagick_output_coder(format)
      normalized = normalize(format)
      IMAGEMAGICK_OUTPUT_CODERS.fetch(normalized) do
        raise UnsupportedFormatError, "unsupported ImageMagick output format: #{normalized.inspect}"
      end
    end
  end

  private_constant :Formats
end
