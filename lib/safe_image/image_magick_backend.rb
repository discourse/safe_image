# frozen_string_literal: true

module SafeImage
  module ImageMagickBackend
    module_function

    DEFAULT_PROFILE = File.expand_path("RT_sRGB.icm", __dir__)

    IMAGEMAGICK_LIMIT_ARGS = %w[
      -limit
      memory
      256MiB
      -limit
      map
      512MiB
      -limit
      disk
      1GiB
      -limit
      area
      128MP
      -limit
      time
      20
      -limit
      thread
      2
    ].freeze

    ALLOWED_FONTS = %w[NimbusSans-Regular DejaVu-Sans Liberation-Sans Arial Helvetica Adwaita-Sans].freeze

    def probe(path, timeout: Runner::DEFAULT_TIMEOUT, max_pixels: nil)
      raise UnsupportedFormatError, "ImageMagick identify not available" unless Runner.available?("identify")
      input, ext, input_arg = imagemagick_input(path, frame: nil)
      stdout, =
        Runner.run!(
          ["identify", *IMAGEMAGICK_LIMIT_ARGS, "-ping", "-format", "%m %w %h %n\n", input_arg],
          timeout: timeout,
          read: [input]
        )
      _magick_format, width, height, frames = stdout.each_line.first.to_s.split
      width = width.to_i
      height = height.to_i
      if max_pixels && width * height > Integer(max_pixels)
        raise LimitError, "image has #{width * height} pixels, exceeds #{max_pixels}"
      end
      { input_format: Formats.normalize(ext), width: width, height: height, frames: frames.to_i, duration_ms: 0.0 }
    end

    def thumbnail(input:, output:, width:, height:, format:, quality:, timeout: Runner::DEFAULT_TIMEOUT)
      resize_like(
        input: input,
        output: output,
        width: width,
        height: height,
        format: format,
        quality: quality,
        crop: :centre,
        timeout: timeout
      )
    end

    def resize_like(input:, output:, width:, height:, format:, quality:, crop: false, timeout: Runner::DEFAULT_TIMEOUT)
      command = convert_command

      input, ext, input_arg = imagemagick_input(input, frame: 0)
      output, output_arg = imagemagick_output(format, output)

      quality = validate_quality!(quality)
      argv = [command, *IMAGEMAGICK_LIMIT_ARGS, input_arg, "-auto-orient"]
      if crop == :north
        argv.concat(
          [
            "-gravity",
            "north",
            "-background",
            "transparent",
            "-thumbnail",
            "#{Integer(width)}x#{Integer(height)}^",
            "-crop",
            "#{Integer(width)}x#{Integer(height)}+0+0",
            "-unsharp",
            "2x0.5+0.7+0",
            "-interlace",
            "none"
          ]
        )
      else
        argv.concat(
          [
            "-gravity",
            "center",
            "-background",
            "transparent",
            "-thumbnail",
            "#{Integer(width)}x#{Integer(height)}^",
            "-extent",
            "#{Integer(width)}x#{Integer(height)}",
            "-interpolate",
            "catrom",
            "-unsharp",
            "2x0.5+0.7+0",
            "-interlace",
            "none"
          ]
        )
      end
      argv.concat(["-profile", DEFAULT_PROFILE]) if File.file?(DEFAULT_PROFILE)
      argv.concat(["-quality", quality.to_s]) if quality
      argv << output_arg

      run_image_command(argv, output, ext, format, timeout, read: [input])
    end

    def downsize(input:, output:, dimensions:, format:, timeout: Runner::DEFAULT_TIMEOUT)
      command = convert_command

      input, ext, input_arg = imagemagick_input(input, frame: 0)
      output, output_arg = imagemagick_output(format, output)
      dimensions = validate_dimensions!(dimensions)
      argv = [
        command,
        *IMAGEMAGICK_LIMIT_ARGS,
        input_arg,
        "-auto-orient",
        "-gravity",
        "center",
        "-background",
        "transparent",
        "-interlace",
        "none",
        "-resize",
        dimensions
      ]
      argv.concat(["-profile", DEFAULT_PROFILE]) if File.file?(DEFAULT_PROFILE)
      argv << output_arg
      run_image_command(argv, output, ext, format, timeout, read: [input])
    end

    def convert(input:, output:, format:, quality: nil, timeout: Runner::DEFAULT_TIMEOUT)
      command = convert_command
      input, ext, input_arg = imagemagick_input(input, frame: 0)
      normalized_format = Formats.normalize(format)
      output, output_arg = imagemagick_output(normalized_format, output)
      quality = validate_quality!(quality)

      argv = [command, *IMAGEMAGICK_LIMIT_ARGS, input_arg, "-auto-orient", "-interlace", "none"]
      argv.concat(%w[-background white -flatten]) if normalized_format == "jpg"
      argv.concat(["-quality", quality.to_s]) if quality
      argv << output_arg
      run_image_command(argv, output, ext, normalized_format, timeout, read: [input])
    end

    def convert_ico_to_png(input:, output:, timeout: Runner::DEFAULT_TIMEOUT)
      command = convert_command
      input, ext, input_arg = imagemagick_input(input, frame: -1)
      raise UnsupportedFormatError, "convert_favicon_to_png requires ico input, got #{ext.inspect}" unless ext == "ico"

      output, output_arg = imagemagick_output("png", output)
      argv = [command, *IMAGEMAGICK_LIMIT_ARGS, input_arg, "-auto-orient", "-background", "transparent", output_arg]
      run_image_command(argv, output, "ico", "png", timeout, read: [input])
    end

    def frame_count(path, timeout: Runner::DEFAULT_TIMEOUT, max_pixels: nil)
      raise UnsupportedFormatError, "ImageMagick identify not available" unless Runner.available?("identify")
      input, _ext, input_arg = imagemagick_input(path, frame: nil)
      stdout, =
        Runner.run!(
          ["identify", *IMAGEMAGICK_LIMIT_ARGS, "-ping", "-format", "%w %h %n\n", input_arg],
          timeout: timeout,
          read: [input]
        )
      width, height, frames = stdout.each_line.first.to_s.split.map(&:to_i)
      if max_pixels && width.to_i * height.to_i > Integer(max_pixels)
        raise LimitError, "image has #{width * height} pixels, exceeds #{max_pixels}"
      end
      frames.to_i
    end

    def orientation(path, timeout: Runner::DEFAULT_TIMEOUT)
      raise UnsupportedFormatError, "ImageMagick identify not available" unless Runner.available?("identify")
      input, _ext, input_arg = imagemagick_input(path, frame: 0)
      stdout, =
        Runner.run!(
          ["identify", *IMAGEMAGICK_LIMIT_ARGS, "-ping", "-format", "%[EXIF:Orientation]", input_arg],
          timeout: timeout,
          read: [input]
        )
      value = stdout.to_s.strip
      value.empty? ? 1 : value.to_i
    rescue CommandError => e
      raise unless missing_orientation_property?(e)

      1
    end

    def missing_orientation_property?(error)
      return false unless error.category == :exit_status

      detail = [error.stderr, error.stdout, error.message].join("\n")
      detail.match?(/EXIF:Orientation|unknown image property|no such (?:property|attribute)|undefined/i)
    end

    # Averages the whole image down to one pixel and reports it as an RRGGBB
    # hex string.
    def dominant_color(path, timeout: Runner::DEFAULT_TIMEOUT)
      command = convert_command
      input, _ext, input_arg = imagemagick_input(path, frame: 0)
      stdout, =
        Runner.run!(
          [
            command,
            *IMAGEMAGICK_LIMIT_ARGS,
            input_arg,
            "-depth",
            "8",
            "-resize",
            "1x1",
            "-define",
            "histogram:unique-colors=true",
            "-format",
            "%c",
            "histogram:info:"
          ],
          timeout: timeout,
          read: [input]
        )

      # Typical output: `1: (110,116,93) #6F745E srgb(110,116,93)`. Alpha adds
      # two more hex digits; grayscale images report one channel (two digits,
      # four with alpha) instead of three.
      digits = stdout[/#(\h+)/, 1]
      hex =
        case digits&.length
        when 6, 8
          digits[0, 6]
        when 2, 4
          digits[0, 2] * 3
        end
      if hex.nil?
        raise InvalidImageError, "could not parse dominant color from ImageMagick output: #{stdout.strip.inspect}"
      end
      hex.upcase
    end

    def letter_avatar(
      output:,
      size:,
      background_rgb:,
      letter:,
      pointsize:,
      font: "NimbusSans-Regular",
      timeout: Runner::DEFAULT_TIMEOUT
    )
      command = convert_command
      output, output_arg = imagemagick_output("png", output)
      rgb = Array(background_rgb).map { |v| Integer(v) }
      raise ArgumentError, "background_rgb must have three channels" unless rgb.length == 3
      glyph = letter.to_s.each_grapheme_cluster.first.to_s.gsub("%", "%%")
      font_name = font.to_s
      if ALLOWED_FONTS.none? { |candidate| candidate == font_name }
        raise ArgumentError, "unsupported font: #{font_name.inspect}"
      end

      argv = [
        command,
        *IMAGEMAGICK_LIMIT_ARGS,
        "-size",
        "#{Integer(size)}x#{Integer(size)}",
        "xc:rgb(#{rgb[0]},#{rgb[1]},#{rgb[2]})",
        "-pointsize",
        Integer(pointsize).to_s,
        "-fill",
        "#FFFFFFCC",
        "-font",
        font_name,
        "-gravity",
        "Center",
        "-annotate",
        "-0+34",
        glyph,
        "-depth",
        "8",
        output_arg
      ]
      run_image_command(argv, output, "generated", "png", timeout)
    end

    def fix_orientation(input:, output:, timeout: Runner::DEFAULT_TIMEOUT)
      command = convert_command
      input, ext, input_arg = imagemagick_input(input, frame: 0)
      output, output_arg = imagemagick_output(ext, output)
      argv = [command, *IMAGEMAGICK_LIMIT_ARGS, input_arg, "-auto-orient", output_arg]
      run_image_command(argv, output, ext, ext, timeout, read: [input])
    end

    def imagemagick_input(input, frame:)
      input = PathSafety.ensure_imagemagick_input_file!(input)
      ext = Formats.extension(input)
      decoder = Formats.imagemagick_decoder(ext)
      frame_suffix = frame.nil? ? "" : "[#{Integer(frame)}]"
      [input, ext, "#{decoder}:#{input}#{frame_suffix}"]
    end

    def imagemagick_output(format, output)
      output = PathSafety.ensure_safe_output_path!(output).to_s
      output = PathSafety.ensure_imagemagick_safe!(output)
      normalized = Formats.normalize(format)
      ext = Formats.extension(output)
      unless ext == normalized
        raise UnsupportedFormatError, "output extension #{ext.inspect} does not match format #{normalized.inspect}"
      end

      [output, "#{Formats.imagemagick_output_coder(normalized)}:#{output}"]
    end

    def validate_quality!(quality)
      return nil if quality.nil?
      quality = Integer(quality)
      raise ArgumentError, "quality must be 1..100" unless (1..100).cover?(quality)
      quality
    end

    def validate_dimensions!(dimensions)
      dimensions = dimensions.to_s
      patterns = [/\A\d+(?:\.\d+)?%\z/, /\A\d+x\d+[!<>^]?\z/, /\A\d+@\z/]
      unless patterns.any? { |pattern| pattern.match?(dimensions) }
        raise ArgumentError, "unsupported ImageMagick geometry: #{dimensions.inspect}"
      end
      dimensions
    end

    def convert_command
      Runner.available?("magick") ? "magick" : Runner.resolve_executable!("convert") && "convert"
    rescue UnsupportedFormatError
      raise UnsupportedFormatError, "ImageMagick convert/magick not available"
    end

    def run_image_command(argv, output, input_format, output_format, timeout, read: [])
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      Runner.run!(argv, timeout: timeout, read: read, write: [File.dirname(output), output])
      duration_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000

      # Output dimensions via the helper's native header read, or identify when
      # the helper is unavailable (this backend must work without libvips).
      info = Native.available? ? Native.probe(output) : probe(output)
      {
        input_format: input_format == "generated" ? "generated" : Formats.normalize(input_format),
        output_format: Formats.normalize(output_format),
        width: info.fetch(:width),
        height: info.fetch(:height),
        duration_ms: duration_ms
      }
    end
  end
end
