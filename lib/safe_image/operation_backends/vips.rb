# frozen_string_literal: true

require_relative "base"

module SafeImage
  module OperationBackends
    # libvips operation orchestration. This is the configured-backend path for
    # untrusted raster bytes; optional cjpegli/jpegtran tiers run only after
    # SafeImage has decoded or validated the input.
    class Vips < Base
      NATIVE_CONVERT_DEFAULT_QUALITY = QualityDefaults::NATIVE_CONVERT_JPEG

      def resize(input:, output:, width:, height:, quality:, optimize:, max_pixels:, chroma_subsampling:)
        input, output = input_output!(input, output)
        max_pixels = resolved_max_pixels(max_pixels)
        result =
          Processor.new(max_pixels: max_pixels, chroma_subsampling: chroma_subsampling, config: config).thumbnail(
            input: input,
            output: output,
            width: width,
            height: height,
            quality: quality || QualityDefaults::JPEG,
            optimize: optimize
          )
        result.with(tier: result.backend.include?("cjpegli") ? :cjpegli : :resize)
      end

      def crop(input:, output:, width:, height:, quality:, optimize:, max_pixels:, chroma_subsampling:)
        input, output = input_output!(input, output)
        max_pixels = resolved_max_pixels(max_pixels)
        probe = operation_probe(input, max_pixels: max_pixels)
        output = safe_output!(output)
        format = Formats.extension(output)

        info =
          if jpegli_for_generated_jpeg?(format)
            JpegliBackend.encode_generated_jpeg(
              output: output,
              quality: quality || JpegliBackend::DEFAULT_QUALITY,
              chroma_subsampling: chroma_subsampling,
              input_format: probe.input_format
            ) do |tmp_path|
              VipsBackend.crop_north(
                input: probe.input,
                output: tmp_path,
                width: width,
                height: height,
                format: "png",
                quality: 100,
                max_pixels: max_pixels
              )
            end
          else
            VipsBackend.crop_north(
              input: probe.input,
              output: output,
              width: width,
              height: height,
              format: format,
              quality: quality || QualityDefaults::JPEG,
              max_pixels: max_pixels
            )
          end
        optimize_output(output, quality) if optimize
        result_from_info(probe.input, output, info, :vips, tier: info[:encoder] == "cjpegli" ? :cjpegli : :crop)
      end

      def downsize(input:, output:, dimensions:, optimize:, max_pixels:, quality:, chroma_subsampling:)
        input, output = input_output!(input, output)
        max_pixels = resolved_max_pixels(max_pixels)
        probe = operation_probe(input, max_pixels: max_pixels)
        output = safe_output!(output)
        format = Formats.extension(output)
        info =
          if jpegli_for_generated_jpeg?(format)
            JpegliBackend.encode_generated_jpeg(
              output: output,
              quality: quality,
              chroma_subsampling: chroma_subsampling,
              input_format: probe.input_format
            ) do |tmp_path|
              VipsBackend.downsize(
                input: probe.input,
                output: tmp_path,
                dimensions: dimensions,
                format: "png",
                quality: 100,
                max_pixels: max_pixels
              )
            end
          else
            VipsBackend.downsize(
              input: probe.input,
              output: output,
              dimensions: dimensions,
              format: format,
              quality: quality,
              max_pixels: max_pixels
            )
          end
        optimize_output(output, nil) if optimize
        result_from_info(probe.input, output, info, :vips, tier: info[:encoder] == "cjpegli" ? :cjpegli : :downsize)
      end

      def convert(input:, output:, format:, quality:, optimize:, max_pixels:, chroma_subsampling:)
        input, output = input_output!(input, output)
        max_pixels = resolved_max_pixels(max_pixels)
        input = PathSafety.ensure_regular_file!(input).to_s
        normalized_format = Formats.normalize(format)

        if jpegli_for_convert?(input, normalized_format)
          info =
            jpegli_convert_after_native_decode(
              input: input,
              output: output,
              quality: quality || JpegliBackend::DEFAULT_QUALITY,
              max_pixels: max_pixels,
              chroma_subsampling: chroma_subsampling
            )
          return result_from_info(input, output, info, :vips, tier: :cjpegli)
        end

        info =
          write_through_tempfile(output) do |tmp_path|
            Native.convert(input, tmp_path, normalized_format, quality || NATIVE_CONVERT_DEFAULT_QUALITY, max_pixels)
          end
        optimize_output(output, normalized_format == "jpg" ? quality : nil) if optimize
        result_from_info(input, output, info, :vips, tier: :native_convert)
      end

      def fix_orientation(input:, output:, max_pixels:, quality:)
        input, output = input_output!(input, output)
        max_pixels = resolved_max_pixels(max_pixels)
        input = PathSafety.ensure_regular_file!(input).to_s
        format = Formats.extension(input)
        # Validates the format against the native loader allowlist and enforces
        # the pixel cap before any pixel decode.
        orient = VipsBackend.orientation(input, max_pixels: max_pixels)

        # Lossless tier: jpegtran transforms JPEG DCT coefficients directly, so
        # there is no generation loss. -perfect refuses when the dimensions are
        # not MCU-aligned; only that expected refusal falls through to the
        # observable re-encode tier.
        tier = :native_reencode
        if format == "jpg" && orient > 1 && Runner.available?("jpegtran")
          begin
            return jpegtran_fix_orientation(input, output, orient)
          rescue CommandError => e
            raise unless Optimizer.jpegtran_perfect_reject?(e)

            tier = :jpegtran_fallback_reencode
          end
        end

        quality = quality.nil? ? QualityDefaults::FIX_ORIENTATION_REENCODE_JPEG : Integer(quality)
        raise ArgumentError, "quality must be 1..100" unless (1..100).cover?(quality)

        info =
          write_through_tempfile(output) { |tmp_path| Native.resize(input, tmp_path, 1.0, format, quality, max_pixels) }
        result_from_info(input, output, info, :vips, tier: tier)
      end

      def convert_favicon_to_png(input:, output:, optimize:, max_pixels:)
        input, output = input_output!(input, output)
        max_pixels = resolved_max_pixels(max_pixels)
        # Pure-Ruby ICO parse; libvips only encodes the extracted pixels.
        info = Ico.convert_to_png(input, output, max_pixels: max_pixels)
        optimize_output(output, nil) if optimize
        result_from_info(input, output, info, :ico_vips, tier: :ico_ruby)
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
        result_from_info("generated", output, VipsBackend.letter_avatar(**request), :vips, tier: :letter_avatar)
      end

      private

      def operation_probe(path, max_pixels:)
        Processor.new(max_pixels: max_pixels, config: config).probe(Pathname.new(path).expand_path.to_s)
      end

      def backend_frame_count(path, max_pixels:)
        VipsBackend.frame_count(path, max_pixels: max_pixels)
      end

      def jpegli_for_convert?(input, normalized_format)
        normalized_format == "jpg" && JpegliBackend.available? && JpegliBackend.suitable_direct_input?(input)
      end

      # cjpegli is an output-quality tool, not a configuration choice: installed
      # means used for JPEG output on the native path. It encodes only pixels
      # this gem already decoded, so it is not part of the untrusted-input
      # surface the backend choice controls.
      def jpegli_for_generated_jpeg?(format)
        Formats.normalize(format) == "jpg" && JpegliBackend.available?
      end

      def jpegli_convert_after_native_decode(input:, output:, quality:, max_pixels:, chroma_subsampling:)
        JpegliBackend.encode_generated_jpeg(
          output: output,
          quality: quality,
          chroma_subsampling: chroma_subsampling
        ) { |tmp_path| Native.convert(input, tmp_path, "png", 100, max_pixels) }
      end

      def jpegtran_fix_orientation(input, output, orient)
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        info =
          write_through_tempfile(output) do |tmp_path|
            Runner.run!(
              [
                "jpegtran",
                "-copy",
                "none",
                "-perfect",
                *Optimizer::JPEGTRAN_OPERATIONS.fetch(orient),
                "-outfile",
                tmp_path,
                input
              ],
              read: [input],
              write: [tmp_path, File.dirname(tmp_path)]
            )
            Native.probe(tmp_path)
          end
        result_from_info(
          input,
          output,
          {
            input_format: "jpg",
            output_format: "jpg",
            width: info.fetch(:width),
            height: info.fetch(:height),
            duration_ms: (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000
          },
          :jpegtran,
          tier: :jpegtran_lossless
        )
      end
    end
  end
end
