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

    OPERATIONS = OperationRegistry.names

    def available?
      require "landlock"
      landlock_supported?
    rescue LoadError
      false
    end

    def landlock_supported?
      Landlock.supported?
    end

    def landlock_command_error
      Landlock::CommandError
    end

    def landlock_abi
      Landlock.abi_version
    end

    def default_read_paths
      %w[/usr /lib /lib64 /etc /bin /sbin /opt].select { |path| File.exist?(path) }
    end

    def default_execute_paths
      %w[/usr /lib /lib64 /bin /sbin /opt].select { |path| File.exist?(path) }
    end

    def landlock_capture!(argv, **options)
      Landlock.capture!(argv.map(&:to_s), allow_all_known: true, **options)
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

    def public_call!(operation, args:, kwargs:, config: SafeImage.config)
      operation = operation.to_s
      raise ArgumentError, "unsupported sandbox operation: #{operation}" if OperationRegistry.exclude?(operation)

      request = { args: args, kwargs: kwargs }
      if config.backend == :vips && native_helper_operation?(operation, request)
        result = native_helper_public_call!(operation, request, config: config)
      else
        result = run_worker!(operation, request, config: config)
      end
      operation == "type" && result ? result.to_sym : result
    end

    def native_helper_operation?(operation, request)
      return false unless OperationRegistry.native_eligible?(operation)
      return false if operation == "thumbnail" && request[:kwargs]&.fetch(:optimize, false)

      path = request[:kwargs]&.fetch(:input, nil) || Array(request[:args]).first
      return true if operation == "thumbnail"
      return false unless path.is_a?(String)

      Formats.native_input?(Formats.extension(path))
    end

    def native_helper_public_call!(operation, request, config: SafeImage.config)
      kwargs = request[:kwargs] || {}
      args = request[:args] || []
      max_pixels = SafeImage.resolved_max_pixels(kwargs[:max_pixels], config: config)

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
      Result.build(
        input: input,
        output: nil,
        input_format: info.fetch(:input_format),
        output_format: nil,
        width: info.fetch(:width),
        height: info.fetch(:height),
        filesize: File.size(input),
        backend: :vips_helper,
        duration_ms: info.fetch(:duration_ms),
        optimizer: nil,
        tier: :native_helper
      )
    end

    def native_helper_thumbnail!(kwargs, max_pixels)
      input, output = PathSafety.ensure_distinct_file_paths!(kwargs.fetch(:input), kwargs.fetch(:output))
      input = input.to_s
      output = output.to_s
      width = Integer(kwargs.fetch(:width))
      height = Integer(kwargs.fetch(:height))
      quality = Integer(kwargs.fetch(:quality, QualityDefaults::JPEG))
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
      Result.build(
        input: input,
        output: output,
        input_format: info.fetch(:input_format),
        output_format: info.fetch(:output_format),
        width: info.fetch(:width),
        height: info.fetch(:height),
        backend: :vips_helper,
        duration_ms: info.fetch(:duration_ms),
        optimizer: opt_info&.fetch(:tools, nil),
        tier: :native_helper
      )
    end

    def optimize_existing_output(output, **options)
      AtomicOutput.replace(output, suffix: ".safe-image#{File.extname(output)}") do |tmp_path|
        Optimizer.optimize(input: output, output: tmp_path, **options)
      end
    end

    def run_worker!(operation, request, config: SafeImage.config)
      operation = operation.to_s
      raise ArgumentError, "unsupported sandbox operation: #{operation}" if OperationRegistry.exclude?(operation)

      require "landlock"
      payload =
        JSON.dump(
          {
            operation: operation,
            # JSON has no symbol type; wrap symbol values so the worker can restore
            # them for keyword values that public APIs accept as symbols.
            request: SandboxProtocol.deep_encode_symbols(request),
            # The worker is a fresh process and must be configured like the
            # parent — minus landlock, since it already runs inside the sandbox.
            config: {
              backend: config.backend,
              max_pixels: config.max_pixels
            }
          }
        )

      paths = sandbox_paths(request, operation)
      worker = File.expand_path("sandbox_worker.rb", __dir__)
      Dir.mktmpdir("safe-image-worker-") do |tmpdir|
        worker_env =
          Runner.command_env(tmpdir).merge(
            "SAFE_IMAGE_SANDBOX_CHILD" => "1",
            "GEM_HOME" => ENV["GEM_HOME"].to_s,
            "GEM_PATH" => ENV["GEM_PATH"].to_s,
            "RUBYLIB" => $LOAD_PATH.select { |p| p && File.directory?(p) }.join(File::PATH_SEPARATOR)
          )

        stdout, stderr =
          landlock_capture!(
            [RbConfig.ruby, "-I#{File.expand_path("../../", __dir__)}", worker, payload],
            read: existing_paths([*default_read_paths, *runtime_read_paths, *paths.fetch(:read), tmpdir, worker]),
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
        decode_worker_stdout(stdout, stderr: stderr)
      end
    rescue LoadError
      raise Error, "landlock sandbox requested but the landlock gem is unavailable"
    rescue landlock_command_error => e
      raise CommandError.new(
              "sandboxed worker failed: #{failure_detail(e)}",
              command: [RbConfig.ruby, File.expand_path("sandbox_worker.rb", __dir__), operation],
              status: e.status&.exitstatus,
              stdout: e.stdout,
              stderr: e.stderr,
              category: :sandbox_worker,
              operation: operation,
              stderr_tail: SandboxProtocol.tail(e.stderr)
            )
    end

    # Rebuilds a worker's {__type:, data:} JSON reply into the value the caller
    # would have received inline. Invalid JSON is reported as a structured
    # boundary error with the worker's stderr tail instead of surfacing as an
    # opaque JSON::ParserError.
    def decode_worker_stdout(stdout, stderr: nil)
      SandboxProtocol.decode_payload(JSON.parse(stdout, symbolize_names: true), stderr: stderr)
    rescue JSON::ParserError => e
      raise CommandError.new(
              "sandboxed worker wrote invalid JSON: #{e.message}",
              command: [RbConfig.ruby, File.expand_path("sandbox_worker.rb", __dir__)],
              stdout: stdout.to_s,
              stderr: stderr.to_s,
              category: :sandbox_worker,
              stderr_tail: SandboxProtocol.tail(stderr)
            )
    end

    def sandbox_paths(request, operation)
      read = expand_read_paths(OperationRegistry.read_paths(operation, request))
      write = expand_write_paths(OperationRegistry.write_paths(operation, request))
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
