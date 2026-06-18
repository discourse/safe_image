# frozen_string_literal: true

module SafeImage
  # One declarative registry for the public operations that may cross the
  # sandbox boundary. Each entry declares whether the native Landlock helper can
  # ever serve the operation, plus the request-derived paths the worker needs as
  # read/write grants. Runtime checks (for example the input format) remain in
  # the caller, but adding/removing an operation is a one-table edit.
  module OperationRegistry
    Operation =
      Struct.new(:native_eligible, :read_paths, :write_paths, keyword_init: true) do
        def native_eligible? = !!native_eligible
        def reads(request) = read_paths.call(request)
        def writes(request) = write_paths.call(request)
      end

    METADATA_INPUT = ->(request) { [Array(request[:args]).first] }
    KEYWORD_INPUT = ->(request) { [request.dig(:kwargs, :input)] }
    KEYWORD_OUTPUT = ->(request) { [request.dig(:kwargs, :output)] }
    NO_PATHS = ->(_request) { [] }

    REGISTRY = {
      "probe" => Operation.new(native_eligible: true, read_paths: METADATA_INPUT, write_paths: NO_PATHS),
      "type" => Operation.new(native_eligible: true, read_paths: METADATA_INPUT, write_paths: NO_PATHS),
      "size" => Operation.new(native_eligible: true, read_paths: METADATA_INPUT, write_paths: NO_PATHS),
      "dimensions" => Operation.new(native_eligible: true, read_paths: METADATA_INPUT, write_paths: NO_PATHS),
      "info" => Operation.new(native_eligible: true, read_paths: METADATA_INPUT, write_paths: NO_PATHS),
      "orientation" => Operation.new(native_eligible: true, read_paths: METADATA_INPUT, write_paths: NO_PATHS),
      "dominant_color" => Operation.new(native_eligible: true, read_paths: METADATA_INPUT, write_paths: NO_PATHS),
      "frame_count" => Operation.new(native_eligible: true, read_paths: METADATA_INPUT, write_paths: NO_PATHS),
      "animated?" => Operation.new(native_eligible: true, read_paths: METADATA_INPUT, write_paths: NO_PATHS),
      "thumbnail" => Operation.new(native_eligible: true, read_paths: KEYWORD_INPUT, write_paths: KEYWORD_OUTPUT),
      "optimize" => Operation.new(native_eligible: false, read_paths: KEYWORD_INPUT, write_paths: KEYWORD_OUTPUT),
      "resize" => Operation.new(native_eligible: false, read_paths: KEYWORD_INPUT, write_paths: KEYWORD_OUTPUT),
      "crop" => Operation.new(native_eligible: false, read_paths: KEYWORD_INPUT, write_paths: KEYWORD_OUTPUT),
      "downsize" => Operation.new(native_eligible: false, read_paths: KEYWORD_INPUT, write_paths: KEYWORD_OUTPUT),
      "convert" => Operation.new(native_eligible: false, read_paths: KEYWORD_INPUT, write_paths: KEYWORD_OUTPUT),
      "fix_orientation" =>
        Operation.new(native_eligible: false, read_paths: KEYWORD_INPUT, write_paths: KEYWORD_OUTPUT),
      "convert_favicon_to_png" =>
        Operation.new(native_eligible: false, read_paths: KEYWORD_INPUT, write_paths: KEYWORD_OUTPUT),
      "letter_avatar" => Operation.new(native_eligible: false, read_paths: NO_PATHS, write_paths: KEYWORD_OUTPUT)
    }.freeze

    module_function

    def names = REGISTRY.keys.freeze

    def include?(operation) = REGISTRY.key?(operation.to_s)

    def exclude?(operation) = !include?(operation)

    def fetch(operation)
      REGISTRY.fetch(operation.to_s) { raise ArgumentError, "unsupported sandbox operation: #{operation}" }
    end

    def native_eligible?(operation) = fetch(operation).native_eligible?

    def read_paths(operation, request) = fetch(operation).reads(request)

    def write_paths(operation, request) = fetch(operation).writes(request)
  end

  private_constant :OperationRegistry
end
