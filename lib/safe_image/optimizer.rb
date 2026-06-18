# frozen_string_literal: true

require "fileutils"

module SafeImage
  module Optimizer
    module_function

    # pngquant's lossy trial is worthwhile only for small generated PNGs; above
    # this size the extra decode/quantize pass is comparatively expensive and
    # oxipng still handles the lossless cleanup.
    MAX_PNGQUANT_SIZE = 500_000

    # EXIF orientation values mapped onto jpegtran's lossless transforms.
    JPEGTRAN_OPERATIONS = {
      2 => %w[-flip horizontal],
      3 => %w[-rotate 180],
      4 => %w[-flip vertical],
      5 => ["-transpose"],
      6 => %w[-rotate 90],
      7 => ["-transverse"],
      8 => %w[-rotate 270]
    }.freeze

    def jpegtran_perfect_reject?(error)
      error.is_a?(CommandError) && error.category == :exit_status && error.status.to_i == 1 &&
        Array(error.command).include?("-perfect")
    end

    # assume_upright: skips the JPEG orientation check; only for callers
    # optimising output this gem just encoded (which is always upright).
    def optimize(
      input:,
      output:,
      mode: :lossless,
      strip_metadata: true,
      quality: nil,
      timeout: Runner::DEFAULT_TIMEOUT,
      strict: true,
      assume_upright: false
    )
      input, output = PathSafety.ensure_distinct_file_paths!(input, output)
      ext = normalized_extension(input)

      AtomicOutput.replace(output, suffix: ".safe-image.#{ext}") do |tmp_path|
        FileUtils.cp(input, tmp_path)
        optimize_working_file!(
          tmp_path,
          mode: mode,
          strip_metadata: strip_metadata,
          quality: quality,
          timeout: timeout,
          strict: strict,
          assume_upright: assume_upright
        )
      end
    end

    def optimize_working_file!(
      path,
      mode: :lossless,
      strip_metadata: true,
      quality: nil,
      timeout: Runner::DEFAULT_TIMEOUT,
      strict: true,
      assume_upright: false
    )
      path = PathSafety.ensure_regular_file!(path)
      ext = normalized_extension(path)
      before = File.size(path)
      state = { tools: [], rotated_from: nil, trimmed: false }

      case ext
      when "jpg"
        skipped =
          optimize_jpeg!(
            path,
            state,
            strip_metadata: strip_metadata,
            quality: quality,
            timeout: timeout,
            strict: strict,
            assume_upright: assume_upright,
            before: before
          )
        return skipped if skipped
      when "png"
        optimize_png!(
          path,
          state,
          mode: mode,
          strip_metadata: strip_metadata,
          quality: quality,
          timeout: timeout,
          strict: strict,
          before: before
        )
      else
        raise UnsupportedFormatError, "unsupported optimize format: #{ext.inspect}"
      end

      build_result(ext, before, File.size(path), state)
    end

    def optimize_jpeg!(path, state, strip_metadata:, quality:, timeout:, strict:, assume_upright:, before:)
      # Stripping metadata deletes the EXIF orientation tag, so an oriented
      # image must have the rotation baked into its pixels first or it ships
      # sideways. jpegtran does that losslessly; without it, leave the file
      # untouched rather than strip-without-rotate.
      orientation = strip_metadata && !assume_upright ? jpeg_orientation(path) : 1
      if orientation > 1
        unless Runner.available?("jpegtran")
          raise Error, "jpegtran is required to optimize a JPEG with EXIF orientation" if strict
          return skipped_result("jpg", before, state.fetch(:tools))
        end

        state[:trimmed] = upright_working_file!(path, orientation, timeout: timeout)
        state[:rotated_from] = orientation
        state[:tools] << "jpegtran"
      end

      if Runner.available?("jpegoptim")
        argv = %w[jpegoptim --quiet]
        argv << (strip_metadata ? "--strip-all" : "--strip-none")
        argv << "--max=#{Integer(quality)}" if quality
        argv << path.to_s
        Runner.run!(argv, timeout: timeout)
        state[:tools] << "jpegoptim"
      else
        raise Error, "jpegoptim is required for strict JPEG optimisation" if strict
      end

      nil
    end

    def optimize_png!(path, state, mode:, strip_metadata:, quality:, timeout:, strict:, before:)
      if mode.to_sym == :lossy && before < MAX_PNGQUANT_SIZE
        pngquant!(path, state, quality: quality, timeout: timeout, strict: strict)
      end
      oxipng!(path, state, strip_metadata: strip_metadata, timeout: timeout, strict: strict)
    end

    def pngquant!(path, state, quality:, timeout:, strict:)
      if Runner.available?("pngquant")
        AtomicOutput.with_temp_path_near(path, suffix: ".pngquant.png") do |tmp_path|
          argv = ["pngquant", "--force", "--skip-if-larger", "--output", tmp_path.to_s]
          argv << "--quality=#{quality}" if quality # e.g. "65-90"
          argv << path.to_s
          skipped = false
          begin
            Runner.run!(argv, timeout: timeout)
          rescue CommandError => e
            # 98: --skip-if-larger declined the result; 99: --quality not met.
            # Both mean "keep the original", not a failure — and the pre-created
            # tempfile is still empty, so it must not win the size comparison.
            raise if [98, 99].none? { |status| status == e.status }
            skipped = true
          end
          if !skipped && tmp_path.file? && File.size(tmp_path).positive? && File.size(tmp_path) < File.size(path)
            FileUtils.mv(tmp_path, path)
            state[:tools] << "pngquant"
          end
        end
      elsif strict
        raise Error, "pngquant is required for strict lossy PNG optimisation"
      end
    end

    def oxipng!(path, state, strip_metadata:, timeout:, strict:)
      if Runner.available?("oxipng")
        argv = %w[oxipng --quiet -o 3]
        argv.concat(["--strip", strip_metadata ? "safe" : "none"])
        argv << path.to_s
        Runner.run!(argv, timeout: timeout)
        state[:tools] << "oxipng"
      else
        raise Error, "oxipng is required for strict PNG optimisation" if strict
      end
    end

    def build_result(format, before, after, state)
      {
        format: format,
        before_bytes: before,
        after_bytes: after,
        saved_bytes: before - after,
        tools: state.fetch(:tools),
        rotated_from: state.fetch(:rotated_from),
        trimmed: state.fetch(:trimmed)
      }
    end

    def skipped_result(format, bytes, tools)
      {
        format: format,
        before_bytes: bytes,
        after_bytes: bytes,
        saved_bytes: 0,
        tools: tools,
        rotated_from: nil,
        trimmed: false
      }
    end

    def normalized_extension(path)
      Formats.extension(path)
    end

    def jpeg_orientation(path)
      case SafeImage.config.backend
      when :vips
        VipsBackend.orientation(path.to_s)
      when :imagemagick
        ImageMagickBackend.orientation(path.to_s)
      end
    end

    # Applies the orientation's lossless jpegtran transform to the working copy,
    # dropping the metadata in the same pass (-copy none; this path only runs
    # when strip_metadata is set). -perfect refuses dimensions that are not
    # MCU-aligned; the -trim retry drops the partial edge blocks (under one MCU,
    # at most 15px) instead of hiding a lossy re-encode here. Returns true when
    # the fallback trimmed.
    def upright_working_file!(path, orientation, timeout:)
      transform = JPEGTRAN_OPERATIONS.fetch(orientation)
      AtomicOutput.with_temp_path_near(path, suffix: ".jpegtran.jpg") do |tmp_path|
        trimmed = false
        begin
          Runner.run!(
            ["jpegtran", "-copy", "none", "-perfect", *transform, "-outfile", tmp_path.to_s, path.to_s],
            timeout: timeout
          )
        rescue CommandError => e
          raise unless jpegtran_perfect_reject?(e)

          Runner.run!(
            ["jpegtran", "-copy", "none", "-trim", *transform, "-outfile", tmp_path.to_s, path.to_s],
            timeout: timeout
          )
          trimmed = true
        end
        FileUtils.mv(tmp_path, path)
        trimmed
      end
    end

    private_class_method :optimize_working_file!,
                         :optimize_jpeg!,
                         :optimize_png!,
                         :pngquant!,
                         :oxipng!,
                         :build_result,
                         :skipped_result,
                         :normalized_extension,
                         :jpeg_orientation,
                         :upright_working_file!
  end
end
