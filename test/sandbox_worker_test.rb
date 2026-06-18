# frozen_string_literal: true

require_relative "test_helper"
require "safe_image/sandbox_worker"
require "stringio"

module SafeImage
  class SandboxWorkerTest < TestCase
    def test_worker_round_trips_symbol_values_without_landlock
      info = run_worker("info", args: [PNG], kwargs: { max_pixels: PNG_PIXELS })

      assert_instance_of Info, info
      assert_equal :png, info.type
      assert_equal [2032, 1312], info.size
    end

    def test_worker_serializes_safe_image_errors
      svg = write_tmp("unsupported.svg", '<svg xmlns="http://www.w3.org/2000/svg" width="1" height="1"></svg>')

      assert_raises(UnsupportedFormatError) { run_worker("dominant_color", args: [svg]) }
    end

    def test_worker_serializes_argument_errors
      assert_raises(ArgumentError) { run_worker("not_a_public_operation") }
    end

    private

    def run_worker(operation, args: [], kwargs: {})
      payload =
        JSON.dump(
          operation: operation,
          request: SandboxProtocol.deep_encode_symbols({ args: args, kwargs: kwargs }),
          config: {
            backend: SafeImage.config.backend,
            max_pixels: SafeImage.config.max_pixels
          }
        )
      out = StringIO.new
      SandboxWorker.run!(payload, out: out)
      out.rewind
      SandboxProtocol.decode_payload(JSON.parse(out.read, symbolize_names: true))
    end
  end
end
