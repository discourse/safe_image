# frozen_string_literal: true

require "json"
require "safe_image" unless defined?(SafeImage::SandboxProtocol)

module SafeImage
  # Executed as a standalone Ruby child by SafeImage::Sandbox. Keeping the child
  # program in a real file gives it syntax checks, backtraces with filenames and
  # direct unit-test coverage.
  module SandboxWorker
    module_function

    def run!(payload_json, out: $stdout)
      payload = JSON.parse(payload_json, symbolize_names: true)
      operation = payload.fetch(:operation).to_s
      raise ArgumentError, "unsupported sandbox operation: #{operation}" if OperationRegistry.exclude?(operation)

      request = SandboxProtocol.deep_decode_symbols(payload.fetch(:request))
      args = request[:args] || []
      kwargs = request[:kwargs] || {}
      config = payload.fetch(:config)

      SafeImage.configure!(
        backend: config.fetch(:backend).to_sym,
        landlock: false,
        max_pixels: config.fetch(:max_pixels)
      )

      result = SafeImage.__send__(operation, *args, **kwargs)
      out.puts JSON.dump(SandboxProtocol.value_payload(result))
    rescue SafeImage::Error, ArgumentError => e
      out.puts JSON.dump(SandboxProtocol.error_payload(e))
    end
  end
end

SafeImage::SandboxWorker.run!(ARGV.fetch(0)) if $PROGRAM_NAME == __FILE__
