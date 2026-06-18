# frozen_string_literal: true

module SafeImage
  # JSON protocol shared by the Landlock parent and sandbox worker. JSON has no
  # symbol type, so symbol values are explicitly wrapped before transport and
  # restored on decode. Keeping this here makes the worker testable and prevents
  # the parent/child encoders from drifting.
  module SandboxProtocol
    module_function

    SYMBOL_VALUE_KEY = "__sym__"
    RESPONSE_TYPE_KEY = "__type"
    STDERR_TAIL_BYTES = 2000

    def value_payload(result)
      if defined?(SafeImage::Result) && result.is_a?(SafeImage::Result)
        { RESPONSE_TYPE_KEY => "Result", "data" => deep_encode_symbols(result.to_h) }
      elsif defined?(SafeImage::Info) && result.is_a?(SafeImage::Info)
        { RESPONSE_TYPE_KEY => "Info", "data" => deep_encode_symbols(result.to_h) }
      else
        { RESPONSE_TYPE_KEY => "Value", "data" => deep_encode_symbols(result) }
      end
    end

    def error_payload(error, stderr: nil)
      payload = {
        RESPONSE_TYPE_KEY => "Error",
        "class" => error.class.name,
        "message" => error.message,
        "stderr_tail" => tail(stderr || boundary_stderr(error))
      }
      if defined?(SafeImage::CommandError) && error.is_a?(SafeImage::CommandError)
        payload.merge!(
          "command" => error.command,
          "status" => error.status,
          "stdout" => error.stdout,
          "stderr" => error.stderr,
          "category" => error.category,
          "operation" => error.operation,
          "original_error_class" => error.original_error_class
        )
      elsif error.respond_to?(:original_error_class)
        payload["original_error_class"] = error.original_error_class
      end
      deep_encode_symbols(payload)
    end

    def decode_payload(response, stderr: nil)
      case response[RESPONSE_TYPE_KEY.to_sym] || response[RESPONSE_TYPE_KEY]
      when "Result"
        data = deep_decode_symbols(response.fetch(:data))
        data[:tier] = nil unless data.key?(:tier)
        Result.new(**data)
      when "Info"
        Info.new(**deep_decode_symbols(response.fetch(:data)))
      when "Error"
        raise_decoded_error(response, stderr: stderr)
      else
        deep_decode_symbols(response[:data])
      end
    end

    def deep_encode_symbols(value)
      case value
      when Symbol
        { SYMBOL_VALUE_KEY => value.to_s }
      when Hash
        value.each_with_object({}) { |(key, child), hash| hash[key] = deep_encode_symbols(child) }
      when Array
        value.map { |child| deep_encode_symbols(child) }
      else
        value
      end
    end

    def deep_decode_symbols(value)
      case value
      when Hash
        symbol_value = value[SYMBOL_VALUE_KEY.to_sym] || value[SYMBOL_VALUE_KEY]
        return symbol_value.to_sym if value.size == 1 && symbol_value.is_a?(String)

        value.transform_values { |child| deep_decode_symbols(child) }
      when Array
        value.map { |child| deep_decode_symbols(child) }
      else
        value
      end
    end

    def tail(value)
      text = value.to_s
      return nil if text.empty?

      text.bytesize > STDERR_TAIL_BYTES ? text.byteslice(-STDERR_TAIL_BYTES, STDERR_TAIL_BYTES) : text
    end

    def safe_image_error_class(class_name)
      class_name = class_name.to_s
      return nil unless class_name.start_with?("SafeImage::")

      klass = class_name.split("::").drop(1).reduce(SafeImage) { |namespace, name| namespace.const_get(name, false) }
      klass if klass.is_a?(Class) && klass <= SafeImage::Error
    rescue NameError
      nil
    end

    def raise_decoded_error(response, stderr: nil)
      class_name = response.fetch(:class).to_s
      message = response.fetch(:message).to_s
      stderr_tail = response[:stderr_tail] || tail(stderr)
      original_class = response[:original_error_class] || class_name
      error_class = safe_image_error_class(class_name)

      if error_class == CommandError
        raise CommandError.new(
                message,
                command: response[:command] || [],
                status: response[:status],
                stdout: response[:stdout].to_s,
                stderr: response[:stderr].to_s,
                category: deep_decode_symbols(response[:category]),
                operation: deep_decode_symbols(response[:operation]),
                original_error_class: original_class,
                stderr_tail: stderr_tail
              )
      end

      raise error_class.new(message, original_error_class: original_class, stderr_tail: stderr_tail) if error_class

      raise ArgumentError, append_boundary_detail(message, stderr_tail) if class_name == "ArgumentError"

      raise Error.new(
              "worker downgraded unknown error class #{class_name.inspect}: #{message}",
              original_error_class: original_class,
              stderr_tail: stderr_tail
            )
    end

    def append_boundary_detail(message, stderr_tail)
      return message if stderr_tail.nil? || stderr_tail.empty?

      "#{message} (worker stderr tail: #{stderr_tail})"
    end

    def boundary_stderr(error)
      error.respond_to?(:stderr_tail) ? error.stderr_tail : nil
    end
  end

  private_constant :SandboxProtocol
end
