# frozen_string_literal: true

module SafeImage
  class Processor
    SUPPORTED_INPUTS = Formats::NATIVE_INPUTS
    SUPPORTED_OUTPUTS = Formats::NATIVE_OUTPUTS
    # Formats the post-processing optimizer tools understand; other outputs
    # skip the optimize pass instead of erroring.
    OPTIMIZABLE_OUTPUTS = Formats::OPTIMIZABLE_OUTPUTS

    def initialize(max_pixels: nil, chroma_subsampling: :auto)
      @max_pixels = max_pixels || SafeImage.config.max_pixels
      @chroma_subsampling = chroma_subsampling
    end

    def probe(path)
      input = safe_existing_file!(path)
      info = Native.probe(input.to_s)
      validate_pixels!(info.fetch(:width), info.fetch(:height))
      Result.new(
        input: input.to_s,
        output: nil,
        input_format: info.fetch(:format),
        output_format: nil,
        width: info.fetch(:width),
        height: info.fetch(:height),
        filesize: File.size(input),
        backend: BackendLabel.build(:vips),
        duration_ms: info.fetch(:duration_ms),
        optimizer: nil
      )
    end

    def thumbnail(input:, output:, width:, height:, format: nil, quality: 85, optimize: false, optimize_mode: :lossless)
      input, output = PathSafety.ensure_distinct_file_paths!(input, output)
      safe_existing_file!(input)
      width = Integer(width)
      height = Integer(height)
      quality = Integer(quality)
      raise ArgumentError, "width and height must be positive" if width <= 0 || height <= 0
      raise ArgumentError, "quality must be 1..100" unless (1..100).cover?(quality)

      out_format = Formats.normalize(format || output.extname.delete_prefix("."))
      unless Formats.native_output?(out_format)
        raise UnsupportedFormatError, "unsupported output format: #{out_format.inspect}"
      end

      output.dirname.mkpath
      backend = SafeImage.config.backend
      info =
        if out_format == "jpg" && use_jpegli_for_generated_jpeg?(backend)
          jpegli_thumbnail(
            input: input,
            output: output,
            width: width,
            height: height,
            quality: quality,
            source_format: input.extname.delete_prefix(".").downcase
          )
        else
          case backend
          when :vips
            Native.thumbnail(input.to_s, output.to_s, width, height, out_format, quality, @max_pixels)
          when :imagemagick
            probe_info = ImageMagickBackend.probe(input.to_s)
            validate_pixels!(probe_info.fetch(:width), probe_info.fetch(:height))
            ImageMagickBackend.thumbnail(
              input: input.to_s,
              output: output.to_s,
              width: width,
              height: height,
              format: out_format,
              quality: quality
            )
          end
        end

      opt_info = nil
      if optimize && OPTIMIZABLE_OUTPUTS.include?(out_format)
        opt_info =
          optimize_output(
            output,
            mode: optimize_mode,
            strip_metadata: true,
            quality: out_format == "jpg" ? quality : nil,
            assume_upright: true
          )
      end

      Result.new(
        input: input.to_s,
        output: output.to_s,
        input_format: info.fetch(:input_format),
        output_format: info.fetch(:output_format),
        width: info.fetch(:width),
        height: info.fetch(:height),
        filesize: File.size(output),
        backend: result_backend(info, backend),
        duration_ms: info.fetch(:duration_ms),
        optimizer: opt_info&.fetch(:tools, nil)
      )
    end

    private

    def optimize_output(output, **options)
      AtomicOutput.replace(output, suffix: ".safe-image#{output.extname}") do |tmp_path|
        Optimizer.optimize(input: output, output: tmp_path, **options)
      end
    end

    # cjpegli is an output-quality tool, not a configuration choice: installed
    # means used. It encodes only pixels this gem already decoded, so it is
    # not part of the untrusted-input surface the backend choice controls.
    def use_jpegli_for_generated_jpeg?(backend)
      backend == :vips && JpegliBackend.available?
    end

    def jpegli_thumbnail(input:, output:, width:, height:, quality:, source_format:)
      AtomicOutput.with_temp_path_near(output, suffix: ".safe-image.png") do |tmp_path|
        Native.thumbnail(input.to_s, tmp_path.to_s, width, height, "png", 100, @max_pixels)
        JpegliBackend.encode(
          input: tmp_path,
          output: output,
          quality: quality,
          chroma_subsampling:
            JpegliBackend.validate_chroma_subsampling!(
              @chroma_subsampling,
              input_format: normalized_source_format(source_format)
            ),
          input_format: normalized_source_format(source_format)
        )
      end
    end

    def normalized_source_format(format)
      Formats.normalize(format)
    end

    def result_backend(info, backend)
      BackendLabel.build(backend, encoder: info[:encoder])
    end

    def safe_existing_file!(path)
      path = PathSafety.ensure_regular_file!(path)
      ext = Formats.extension(path)
      raise UnsupportedFormatError, "unsupported input format: #{ext.inspect}" unless Formats.native_input?(ext)
      path
    end

    def validate_pixels!(width, height)
      return unless @max_pixels
      pixels = Integer(width) * Integer(height)
      raise LimitError, "image has #{pixels} pixels, exceeds #{@max_pixels}" if pixels > @max_pixels
    end
  end
end
