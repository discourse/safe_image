# frozen_string_literal: true

require "json"
require "rbconfig"
require "tmpdir"

module SafeImage
  module NativeHelper
    module_function

    HELPER = File.expand_path("safe_image_vips_helper", __dir__)

    def available?
      File.executable?(HELPER)
    end

    def ensure_available!
      return if available?

      raise VipsUnavailableError, "compiled safe_image_vips_helper is missing or not executable: #{HELPER}"
    end

    def probe(path, max_pixels)
      call!("probe", input: path, max_pixels: max_pixels)
    end

    def thumbnail(input, output, width, height, format, quality, max_pixels)
      call!(
        "thumbnail",
        input: input,
        output: output,
        width: width,
        height: height,
        format: format,
        quality: quality,
        max_pixels: max_pixels
      )
    end

    def resize(input, output, scale, format, quality, max_pixels)
      call!(
        "resize",
        input: input,
        output: output,
        scale: scale,
        format: format,
        quality: quality,
        max_pixels: max_pixels
      )
    end

    def crop_north(input, output, width, height, format, quality, max_pixels)
      call!(
        "crop-north",
        input: input,
        output: output,
        width: width,
        height: height,
        format: format,
        quality: quality,
        max_pixels: max_pixels
      )
    end

    def convert(input, output, format, quality, max_pixels)
      call!("convert", input: input, output: output, format: format, quality: quality, max_pixels: max_pixels)
    end

    def dominant_color(path, max_pixels)
      call!("dominant-color", input: path, max_pixels: max_pixels).fetch(:value)
    end

    def pages(path, max_pixels)
      call!("pages", input: path, max_pixels: max_pixels).fetch(:value)
    end

    def orientation(path, max_pixels)
      call!("orientation", input: path, max_pixels: max_pixels).fetch(:value)
    end

    def call!(command, **options)
      ensure_available!
      require "landlock"

      Dir.mktmpdir("safe-image-vips-helper-") do |tmpdir|
        response = File.join(tmpdir, "response.json")
        argv = [HELPER, command, "--response", response]
        options.each do |key, value|
          next if value.nil?

          argv << "--#{key.to_s.tr("_", "-")}" << value.to_s
        end

        status =
          Sandbox.landlock_exec(
            argv,
            read:
              Sandbox.existing_paths([*Sandbox.default_read_paths, *Sandbox.runtime_read_paths, *read_paths(options)]),
            write: Sandbox.existing_paths([tmpdir, *write_paths(options)]),
            execute: Sandbox.existing_paths([File.dirname(HELPER), *Sandbox.default_execute_paths]),
            env: Runner.command_env(tmpdir).merge("SAFE_IMAGE_SANDBOX_CHILD" => "1"),
            unsetenv_others: true,
            bind_tcp: landlock_abi >= 4 ? [1] : [],
            scope: landlock_abi >= 6 ? %i[abstract_unix_socket signal] : []
          )

        payload = read_response(response)
        raise_helper_error(payload, status) unless status.success? && payload[:ok]
        payload.reject { |key, _| key == :ok }
      end
    rescue LoadError
      raise Error, "landlock sandbox requested but the landlock gem is unavailable"
    end

    def landlock_abi
      @landlock_abi ||= Landlock.abi_version
    end

    def read_response(path)
      JSON.parse(File.read(path), symbolize_names: true)
    rescue Errno::ENOENT
      { ok: false, error: "CommandError", message: "native vips helper did not write a response" }
    rescue JSON::ParserError => e
      { ok: false, error: "CommandError", message: "native vips helper wrote invalid JSON: #{e.message}" }
    end

    def raise_helper_error(payload, status)
      message =
        payload[:message].to_s.empty? ? "native vips helper failed with status #{status.exitstatus}" : payload[:message]
      case payload[:error].to_s
      when "LimitError"
        raise LimitError, message
      when "UnsupportedFormatError"
        raise UnsupportedFormatError, message
      when "VipsUnavailableError"
        raise VipsUnavailableError, message
      when "ArgumentError"
        raise ArgumentError, message
      when "InvalidImageError", ""
        raise InvalidImageError, message
      else
        raise CommandError.new(
                message,
                command: [HELPER],
                status: status.exitstatus,
                category: :native_helper,
                operation: command
              )
      end
    end

    def read_paths(options)
      [options[:input]].compact
    end

    def write_paths(options)
      output = options[:output]
      return [] unless output

      expanded = File.expand_path(output)
      paths = [File.dirname(expanded)]
      paths << expanded if File.exist?(expanded)
      paths
    end
  end
end
