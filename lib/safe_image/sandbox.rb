# frozen_string_literal: true

require "fileutils"
require "json"
require "rbconfig"
require "tmpdir"

module SafeImage
  module Sandbox
    module_function

    DEFAULT_RLIMITS = {
      cpu_seconds: 30,
      memory_bytes: 2 * 1024 * 1024 * 1024,
      file_size_bytes: 1024 * 1024 * 1024,
      open_files: 256
    }.freeze

    OPERATIONS = %w[
      probe
      thumbnail
      type
      size
      dimensions
      info
      orientation
      dominant_color
      optimize
      resize
      crop
      downsize
      convert
      fix_orientation
      convert_favicon_to_png
      frame_count
      animated?
      letter_avatar
    ].freeze

    METADATA_INPUT = ->(request) { [Array(request[:args]).first] }
    KEYWORD_INPUT = ->(request) { [request.dig(:kwargs, :input)] }
    KEYWORD_OUTPUT = ->(request) { [request.dig(:kwargs, :output)] }
    NO_PATHS = ->(_request) { [] }

    OPERATION_PATHS = {
      "probe" => {
        read: METADATA_INPUT,
        write: NO_PATHS
      },
      "type" => {
        read: METADATA_INPUT,
        write: NO_PATHS
      },
      "size" => {
        read: METADATA_INPUT,
        write: NO_PATHS
      },
      "dimensions" => {
        read: METADATA_INPUT,
        write: NO_PATHS
      },
      "info" => {
        read: METADATA_INPUT,
        write: NO_PATHS
      },
      "orientation" => {
        read: METADATA_INPUT,
        write: NO_PATHS
      },
      "dominant_color" => {
        read: METADATA_INPUT,
        write: NO_PATHS
      },
      "frame_count" => {
        read: METADATA_INPUT,
        write: NO_PATHS
      },
      "animated?" => {
        read: METADATA_INPUT,
        write: NO_PATHS
      },
      "thumbnail" => {
        read: KEYWORD_INPUT,
        write: KEYWORD_OUTPUT
      },
      "optimize" => {
        read: KEYWORD_INPUT,
        write: KEYWORD_OUTPUT
      },
      "resize" => {
        read: KEYWORD_INPUT,
        write: KEYWORD_OUTPUT
      },
      "crop" => {
        read: KEYWORD_INPUT,
        write: KEYWORD_OUTPUT
      },
      "downsize" => {
        read: KEYWORD_INPUT,
        write: KEYWORD_OUTPUT
      },
      "convert" => {
        read: KEYWORD_INPUT,
        write: KEYWORD_OUTPUT
      },
      "fix_orientation" => {
        read: KEYWORD_INPUT,
        write: KEYWORD_OUTPUT
      },
      "convert_favicon_to_png" => {
        read: KEYWORD_INPUT,
        write: KEYWORD_OUTPUT
      },
      "letter_avatar" => {
        read: NO_PATHS,
        write: KEYWORD_OUTPUT
      }
    }.freeze

    def available?
      require "landlock"
      landlock_supported?
    rescue LoadError
      false
    end

    def landlock_supported?
      defined?(Landlock::SafeExec) ? Landlock::SafeExec.supported? : Landlock.supported?
    end

    def landlock_command_error
      defined?(Landlock::SafeExec::CommandError) ? Landlock::SafeExec::CommandError : Landlock::CommandError
    end

    def landlock_abi
      Landlock.respond_to?(:abi_version) ? Landlock.abi_version : 0
    end

    def default_read_paths
      if defined?(Landlock::SafeExec) && Landlock::SafeExec.respond_to?(:default_read_paths)
        Landlock::SafeExec.default_read_paths
      else
        %w[/usr /lib /lib64 /etc /bin /sbin /opt].select { |path| File.exist?(path) }
      end
    end

    def default_execute_paths
      if defined?(Landlock::SafeExec) && Landlock::SafeExec.respond_to?(:default_execute_paths)
        Landlock::SafeExec.default_execute_paths
      else
        %w[/usr /lib /lib64 /bin /sbin /opt].select { |path| File.exist?(path) }
      end
    end

    def landlock_capture!(argv, **options)
      if defined?(Landlock::SafeExec)
        inherit_env = options.delete(:unsetenv_others)
        options[:inherit_env] = !inherit_env unless inherit_env.nil?
        Landlock::SafeExec.capture!(*argv.map(&:to_s), **options)
      else
        Landlock.capture!(argv.map(&:to_s), allow_all_known: true, **options)
      end
    end

    def landlock_exec(argv, **options)
      if defined?(Landlock::SafeExec) && Landlock::SafeExec.respond_to?(:exec)
        inherit_env = options.delete(:unsetenv_others)
        options[:inherit_env] = !inherit_env unless inherit_env.nil?
        Landlock::SafeExec.exec(*argv.map(&:to_s), **options)
      else
        Landlock.exec(argv.map(&:to_s), allow_all_known: true, **options)
      end
    end

    def capture_command!(argv, read:, write:, timeout: Runner::DEFAULT_TIMEOUT, env: nil, rlimits: DEFAULT_RLIMITS)
      require "landlock"
      env ||= Runner.command_env(Dir.tmpdir)

      result =
        landlock_capture!(
          argv,
          read: existing_paths([*default_read_paths, *runtime_read_paths, *read]),
          write: existing_paths(write),
          execute: existing_paths([*default_execute_paths, File.dirname(RbConfig.ruby)]),
          env: env.merge("SAFE_IMAGE_SANDBOX_CHILD" => "1"),
          unsetenv_others: true,
          timeout: timeout,
          rlimits: rlimits,
          seccomp_deny_network: true,
          max_output_bytes: 512 * 1024,
          truncate_output: false
        )
      [result.stdout, result.stderr]
    rescue LoadError
      raise Error, "landlock sandbox requested but the landlock gem is unavailable"
    rescue landlock_command_error => e
      raise CommandError.new(
              "sandboxed command failed: #{failure_detail(e)}",
              command: argv,
              status: e.status&.exitstatus,
              stdout: e.stdout,
              stderr: e.stderr,
              category: :sandbox_command
            )
    end

    def public_call!(operation, args:, kwargs:)
      operation = operation.to_s
      if OPERATIONS.none? { |candidate| candidate == operation }
        raise ArgumentError, "unsupported sandbox operation: #{operation}"
      end
      request = { args: args, kwargs: kwargs }
      if SafeImage.config.backend == :vips && native_helper_operation?(operation, request)
        result = native_helper_public_call!(operation, request)
      else
        result = run_worker!(operation, request)
      end
      operation == "type" && result ? result.to_sym : result
    end

    def native_helper_operation?(operation, request)
      return false if operation == "thumbnail" && request[:kwargs]&.fetch(:optimize, false)
      if %w[
           probe
           type
           size
           dimensions
           info
           orientation
           dominant_color
           frame_count
           animated?
           thumbnail
         ].none? { |candidate| candidate == operation }
        return false
      end

      path = request[:kwargs]&.fetch(:input, nil) || Array(request[:args]).first
      return true if operation == "thumbnail"
      return false unless path.is_a?(String)

      ext = Formats.extension(path)
      Formats.native_input?(ext)
    rescue Error, ArgumentError
      false
    end

    def native_helper_public_call!(operation, request)
      kwargs = request[:kwargs] || {}
      args = request[:args] || []
      max_pixels = SafeImage.resolved_max_pixels(kwargs[:max_pixels])

      case operation
      when "probe"
        result_from_helper_probe(args.fetch(0), max_pixels)
      when "type"
        SafeImage.__send__(:fastimage_type, result_from_helper_probe(args.fetch(0), max_pixels).input_format)
      when "size", "dimensions"
        result = result_from_helper_probe(args.fetch(0), max_pixels)
        [result.width, result.height]
      when "info"
        result = result_from_helper_probe(args.fetch(0), max_pixels)
        Info.new(
          path: result.input,
          type: SafeImage.__send__(:fastimage_type, result.input_format),
          width: result.width,
          height: result.height,
          size: [result.width, result.height],
          animated: kwargs[:animated] ? NativeHelper.pages(result.input, max_pixels).to_i > 1 : nil,
          orientation: kwargs[:orientation] ? NativeHelper.orientation(result.input, max_pixels) : nil
        )
      when "orientation"
        NativeHelper.orientation(PathSafety.ensure_regular_file!(args.fetch(0)).to_s, max_pixels)
      when "dominant_color"
        NativeHelper.dominant_color(PathSafety.ensure_regular_file!(args.fetch(0)).to_s, max_pixels)
      when "frame_count"
        NativeHelper.pages(PathSafety.ensure_regular_file!(args.fetch(0)).to_s, max_pixels)
      when "animated?"
        NativeHelper.pages(PathSafety.ensure_regular_file!(args.fetch(0)).to_s, max_pixels).to_i > 1
      when "thumbnail"
        native_helper_thumbnail!(kwargs, max_pixels)
      else
        raise ArgumentError, "unsupported native helper operation: #{operation}"
      end
    end

    def result_from_helper_probe(path, max_pixels)
      input = PathSafety.ensure_regular_file!(path).to_s
      info = NativeHelper.probe(input, max_pixels)
      Result.new(
        input: input,
        output: nil,
        input_format: info.fetch(:input_format),
        output_format: nil,
        width: info.fetch(:width),
        height: info.fetch(:height),
        filesize: File.size(input),
        backend: "libvips-helper",
        duration_ms: info.fetch(:duration_ms),
        optimizer: nil
      )
    end

    def native_helper_thumbnail!(kwargs, max_pixels)
      input, output = PathSafety.ensure_distinct_file_paths!(kwargs.fetch(:input), kwargs.fetch(:output))
      input = input.to_s
      output = output.to_s
      width = Integer(kwargs.fetch(:width))
      height = Integer(kwargs.fetch(:height))
      quality = Integer(kwargs.fetch(:quality, 85))
      format = Formats.normalize(kwargs[:format] || File.extname(output).delete_prefix("."))
      FileUtils.mkdir_p(File.dirname(output))
      info = NativeHelper.thumbnail(input, output, width, height, format, quality, max_pixels)
      opt_info = nil
      if kwargs[:optimize] && Formats.optimizable_output?(format)
        opt_info =
          optimize_existing_output(
            output,
            mode: kwargs.fetch(:optimize_mode, :lossless),
            strip_metadata: true,
            quality: format == "jpg" ? quality : nil,
            assume_upright: true
          )
      end
      Result.new(
        input: input,
        output: output,
        input_format: info.fetch(:input_format),
        output_format: info.fetch(:output_format),
        width: info.fetch(:width),
        height: info.fetch(:height),
        filesize: File.size(output),
        backend: "libvips-helper",
        duration_ms: info.fetch(:duration_ms),
        optimizer: opt_info&.fetch(:tools, nil)
      )
    end

    def optimize_existing_output(output, **options)
      AtomicOutput.replace(output, suffix: ".safe-image#{File.extname(output)}") do |tmp_path|
        Optimizer.optimize(input: output, output: tmp_path, **options)
      end
    end

    def run_worker!(operation, request)
      operation = operation.to_s
      if OPERATIONS.none? { |candidate| candidate == operation }
        raise ArgumentError, "unsupported sandbox operation: #{operation}"
      end

      require "landlock"
      config = SafeImage.config
      payload =
        JSON.dump(
          {
            operation: operation,
            # JSON has no symbol type; wrap symbol values so the worker can restore
            # them for keyword values that public APIs accept as symbols.
            request: deep_encode_symbols(request),
            # The worker is a fresh process and must be configured like the
            # parent — minus landlock, since it already runs inside the sandbox.
            config: {
              backend: config.backend,
              max_pixels: config.max_pixels
            }
          }
        )
      code = <<~'RUBY'
        require "json"
        require "safe_image"

        def deep_symbolize(value)
          case value
          when Hash
            # {"__sym__" => "x"} is a symbol value the parent wrapped for transport.
            return value[:__sym__].to_sym if value.size == 1 && value[:__sym__].is_a?(String)
            value.each_with_object({}) { |(k, v), h| h[k.to_sym] = deep_symbolize(v) }
          when Array
            value.map { |v| deep_symbolize(v) }
          else
            value
          end
        end

        def deep_encode_symbols(value)
          case value
          when Symbol
            { __sym__: value.to_s }
          when Hash
            value.transform_values { |v| deep_encode_symbols(v) }
          when Array
            value.map { |v| deep_encode_symbols(v) }
          else
            value
          end
        end

        payload = JSON.parse(ARGV.fetch(0), symbolize_names: true)
        operation = payload.fetch(:operation).to_s
        allowed_operations = %w[
          probe thumbnail type size dimensions info orientation dominant_color optimize resize crop downsize convert fix_orientation
          convert_favicon_to_png frame_count animated? letter_avatar
        ]
        raise ArgumentError, "unsupported sandbox operation: #{operation}" unless allowed_operations.include?(operation)

        request = deep_symbolize(payload.fetch(:request))
        args = request[:args] || []
        kwargs = request[:kwargs] || {}

        config = payload.fetch(:config)
        SafeImage.configure!(
          backend: config.fetch(:backend).to_sym,
          landlock: false,
          max_pixels: config.fetch(:max_pixels)
        )

        begin
          result = SafeImage.__send__(operation, *args, **kwargs)

          if defined?(SafeImage::Result) && result.is_a?(SafeImage::Result)
            puts JSON.dump({ __type: "Result", data: deep_encode_symbols(result.to_h) })
          elsif defined?(SafeImage::Info) && result.is_a?(SafeImage::Info)
            puts JSON.dump({ __type: "Info", data: deep_encode_symbols(result.to_h) })
          else
            puts JSON.dump({ __type: "Value", data: deep_encode_symbols(result) })
          end
        rescue SafeImage::Error => e
          error = { __type: "Error", class: e.class.name, message: e.message }
          if defined?(SafeImage::CommandError) && e.is_a?(SafeImage::CommandError)
            error[:command] = e.command
            error[:status] = e.status
            error[:stdout] = e.stdout
            error[:stderr] = e.stderr
            error[:category] = e.category
            error[:operation] = e.operation
          end
          puts JSON.dump(error)
        end
      RUBY

      paths = sandbox_paths(request, operation)
      Dir.mktmpdir("safe-image-worker-") do |tmpdir|
        worker_env =
          Runner.command_env(tmpdir).merge(
            "SAFE_IMAGE_SANDBOX_CHILD" => "1",
            "GEM_HOME" => ENV["GEM_HOME"].to_s,
            "GEM_PATH" => ENV["GEM_PATH"].to_s,
            "RUBYLIB" => $LOAD_PATH.select { |p| p && File.directory?(p) }.join(File::PATH_SEPARATOR)
          )

        stdout, =
          landlock_capture!(
            [RbConfig.ruby, "-I#{File.expand_path("../../", __dir__)}", "-rjson", "-e", code, payload],
            read: existing_paths([*default_read_paths, *runtime_read_paths, *paths.fetch(:read), tmpdir]),
            write: existing_paths([*paths.fetch(:write), tmpdir]),
            execute: existing_paths([*default_execute_paths, File.dirname(RbConfig.ruby)]),
            env: worker_env,
            unsetenv_others: true,
            timeout: Runner::DEFAULT_TIMEOUT,
            rlimits: DEFAULT_RLIMITS,
            seccomp_deny_network: true,
            max_output_bytes: 512 * 1024,
            truncate_output: false
          )
        decode_payload(JSON.parse(stdout, symbolize_names: true))
      end
    rescue LoadError
      raise Error, "landlock sandbox requested but the landlock gem is unavailable"
    rescue landlock_command_error => e
      raise CommandError.new(
              "sandboxed worker failed: #{failure_detail(e)}",
              command: [RbConfig.ruby, "-e", "..."],
              status: e.status&.exitstatus,
              stdout: e.stdout,
              stderr: e.stderr,
              category: :sandbox_worker,
              operation: operation
            )
    end

    # Rebuilds a worker's {__type:, data:} JSON reply into the value the
    # caller would have received inline.
    def decode_payload(response)
      case response[:__type]
      when "Result"
        Result.new(**deep_decode_symbols(response.fetch(:data)))
      when "Info"
        Info.new(**deep_decode_symbols(response.fetch(:data)))
      when "Error"
        error_class = safe_image_error_class(response.fetch(:class))
        if error_class == CommandError
          raise CommandError.new(
                  response.fetch(:message).to_s,
                  command: response[:command] || [],
                  status: response[:status],
                  stdout: response[:stdout].to_s,
                  stderr: response[:stderr].to_s,
                  category: response[:category],
                  operation: response[:operation]
                )
        end
        raise error_class, response.fetch(:message).to_s
      else
        deep_decode_symbols(response[:data])
      end
    end

    def safe_image_error_class(class_name)
      klass = class_name.to_s.split("::").reduce(Object) { |namespace, name| namespace.const_get(name, false) }
      return klass if klass <= SafeImage::Error

      SafeImage::Error
    rescue NameError
      SafeImage::Error
    end

    # JSON cannot represent symbols, so wrap symbol values as {"__sym__" => name}
    # for the worker's deep_symbolize to restore. Mirrors that decoder.
    def deep_encode_symbols(value)
      case value
      when Symbol
        { "__sym__" => value.to_s }
      when Hash
        value.transform_values { |v| deep_encode_symbols(v) }
      when Array
        value.map { |v| deep_encode_symbols(v) }
      else
        value
      end
    end

    def deep_decode_symbols(value)
      case value
      when Hash
        return value[:__sym__].to_sym if value.size == 1 && value[:__sym__].is_a?(String)

        value.transform_values { |v| deep_decode_symbols(v) }
      when Array
        value.map { |v| deep_decode_symbols(v) }
      else
        value
      end
    end

    def sandbox_paths(request, operation)
      rules =
        OPERATION_PATHS.fetch(operation.to_s) { raise ArgumentError, "unsupported sandbox operation: #{operation}" }
      read = expand_read_paths(rules.fetch(:read).call(request))
      write = expand_write_paths(rules.fetch(:write).call(request))
      { read: read.uniq, write: write.uniq }
    end

    def expand_read_paths(paths)
      Array(paths).flatten.compact.filter_map do |path|
        next unless path.is_a?(String)
        next if path.empty? || path.include?("\0")

        File.expand_path(path)
      rescue StandardError
        nil
      end
    end

    def expand_write_paths(paths)
      Array(paths).flatten.compact.flat_map do |path|
        next [] unless path.is_a?(String)
        next [] if path.empty? || path.include?("\0")

        expanded = File.expand_path(path)
        targets = [File.dirname(expanded)]
        targets << expanded if File.exist?(expanded)
        targets
      rescue StandardError
        []
      end
    end

    def runtime_read_paths
      paths = []
      paths.concat(Gem.path) if defined?(Gem)
      paths.concat($LOAD_PATH.select { |path| path && path != "." })
      paths << RbConfig::CONFIG["rubylibdir"]
      paths << RbConfig::CONFIG["rubyarchdir"]
      paths << RbConfig::CONFIG["sitearchdir"]
      paths << RbConfig::CONFIG["vendorarchdir"]
      # An --enable-shared Ruby installed outside the default read roots
      # (e.g. GitHub Actions' /opt/hostedtoolcache builds) keeps libruby in
      # libdir; without read access the worker dies at dynamic-link time
      # before any Ruby code runs.
      paths << RbConfig::CONFIG["libdir"]
      paths << File.dirname(RbConfig.ruby)
      # Pango/fontconfig need the font directories and configs for the native
      # letter_avatar text rendering inside the worker.
      paths << "/etc/fonts"
      paths << "/usr/share/fonts"
      paths << "/usr/local/share/fonts"
      paths << "/var/cache/fontconfig"
      paths
    end

    def existing_paths(paths)
      paths.flatten.compact.map(&:to_s).reject(&:empty?).select { |path| File.exist?(path) }.uniq
    end

    # Sandbox failures often happen before the child can run any Ruby (e.g. a
    # denied shared-library read kills it at dynamic-link time); without the
    # child's stderr in the message they are undiagnosable from a CI log.
    def failure_detail(error)
      detail = error.stderr.to_s.strip
      detail = "exit status #{error.status&.exitstatus.inspect}" if detail.empty?
      detail[0, 2000]
    end

    def symbolize(hash)
      hash.transform_keys(&:to_sym)
    end
  end
end
