# frozen_string_literal: true

module SafeImage
  module JpegliBackend
    module_function

    DIRECT_INPUTS = Formats::CJPEGLI_DIRECT_INPUTS
    CHROMA_SUBSAMPLING = %w[420 422 444].freeze
    DEFAULT_QUALITY = QualityDefaults::JPEG

    def available?
      Runner.available?("cjpegli")
    end

    def suitable_direct_input?(input)
      Formats.cjpegli_direct_input?(normalized_ext(input))
    end

    def convert(input:, output:, quality: DEFAULT_QUALITY, chroma_subsampling: :auto, timeout: Runner::DEFAULT_TIMEOUT)
      raise UnsupportedFormatError, "cjpegli is not installed" unless available?

      input = PathSafety.ensure_regular_file!(input)
      output = PathSafety.ensure_safe_output_path!(output).to_s
      ensure_jpeg_output!(output)

      input_format = normalized_ext(input)
      if DIRECT_INPUTS.none? { |candidate| candidate == input_format }
        raise UnsupportedFormatError, "cjpegli direct input format is unsupported: #{input_format.inspect}"
      end

      quality = validate_quality!(quality)
      chroma_subsampling = validate_chroma_subsampling!(chroma_subsampling, input_format: input_format)
      encode(
        input: input,
        output: output,
        quality: quality,
        chroma_subsampling: chroma_subsampling,
        timeout: timeout,
        input_format: input_format
      )
    end

    def encode_generated_jpeg(output:, quality: DEFAULT_QUALITY, chroma_subsampling: :auto, input_format: nil)
      AtomicOutput.with_temp_path_near(output, suffix: ".safe-image.png") do |tmp_path|
        decoded = yield tmp_path
        source_format = input_format || decoded.fetch(:input_format)
        encode(
          input: tmp_path,
          output: output,
          quality: quality,
          chroma_subsampling: validate_chroma_subsampling!(chroma_subsampling, input_format: source_format),
          input_format: source_format
        )
      end
    end

    def encode(
      input:,
      output:,
      quality: DEFAULT_QUALITY,
      chroma_subsampling: "420",
      timeout: Runner::DEFAULT_TIMEOUT,
      input_format: nil
    )
      raise UnsupportedFormatError, "cjpegli is not installed" unless available?

      input = PathSafety.ensure_regular_file!(input)
      output_path = PathSafety.ensure_safe_output_path!(output)
      ensure_jpeg_output!(output_path)
      output_path.dirname.mkpath

      input_format ||= normalized_ext(input)
      quality = validate_quality!(quality)
      chroma_subsampling = validate_chroma_subsampling!(chroma_subsampling, input_format: input_format)

      info =
        AtomicOutput.replace(output_path, suffix: ".cjpegli.jpg") do |tmp_path|
          argv = [
            "cjpegli",
            input.to_s,
            tmp_path.to_s,
            "--quality=#{quality}",
            "--chroma_subsampling=#{chroma_subsampling}"
          ]
          Runner.run!(argv, timeout: timeout, read: [input.to_s], write: [output_path.dirname.to_s])
          raise Error, "cjpegli did not create output" unless tmp_path.file? && File.size(tmp_path).positive?

          # cjpegli works without libvips; fall back to identify for the
          # output dimensions when the native header read is unavailable.
          info = VipsGlue.available? ? Native.probe(tmp_path.to_s) : ImageMagickBackend.probe(tmp_path.to_s)
          {
            input_format: input_format,
            output_format: "jpg",
            width: info.fetch(:width),
            height: info.fetch(:height),
            duration_ms: info.fetch(:duration_ms),
            encoder: "cjpegli",
            chroma_subsampling: chroma_subsampling
          }
        end
      info
    end

    def validate_quality!(quality)
      quality = DEFAULT_QUALITY if quality.nil?
      quality = Integer(quality)
      raise ArgumentError, "quality must be 1..100" unless (1..100).cover?(quality)
      quality
    end

    def validate_chroma_subsampling!(value, input_format: nil)
      value = :auto if value.nil?
      value = "444" if value.to_sym == :auto && input_format.to_s == "png"
      value = "420" if value.to_sym == :auto
      value = value.to_s
      if CHROMA_SUBSAMPLING.none? { |candidate| candidate == value }
        raise ArgumentError, "chroma_subsampling must be one of #{CHROMA_SUBSAMPLING.join(", ")}"
      end
      value
    end

    def ensure_jpeg_output!(output)
      ext = normalized_ext(output)
      raise UnsupportedFormatError, "cjpegli only outputs jpg/jpeg, got #{ext.inspect}" unless ext == "jpg"
    end

    def normalized_ext(path)
      Formats.extension(path)
    end
  end
end
