# frozen_string_literal: true

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
      # libdir; helper/tool subprocesses need read access before they can start.
      paths << RbConfig::CONFIG["libdir"]
      paths << File.dirname(RbConfig.ruby)
      # Pango/fontconfig need the font directories and configs for the native
      # letter_avatar text rendering inside the helper.
      paths << "/etc/fonts"
      paths << "/usr/share/fonts"
      paths << "/usr/local/share/fonts"
      paths << "/var/cache/fontconfig"
      paths
    end

    def existing_paths(paths)
      paths.flatten.compact.map(&:to_s).reject(&:empty?).select { |path| File.exist?(path) }.uniq
    end

    # Sandbox failures often happen before the child can write structured output
    # (e.g. a denied shared-library read kills it at dynamic-link time); include
    # stderr so CI logs remain diagnosable.
    def failure_detail(error)
      detail = error.stderr.to_s.strip
      detail = "exit status #{error.status&.exitstatus.inspect}" if detail.empty?
      detail[0, 2000]
    end
  end
end
