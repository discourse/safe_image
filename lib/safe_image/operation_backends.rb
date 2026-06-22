# frozen_string_literal: true

require_relative "operation_backends/base"
require_relative "operation_backends/vips"
require_relative "operation_backends/image_magick"

module SafeImage
  # Factory for operation orchestration strategies. Transform and metadata
  # operation objects select one strategy per call from the supplied config; the
  # strategy owns the backend-specific pipeline details.
  module OperationBackends
    module_function

    def for(config)
      case config.backend
      when :vips
        Vips.new(config: config)
      when :imagemagick
        ImageMagick.new(config: config)
      else
        raise ArgumentError, "unknown backend: #{config.backend.inspect}"
      end
    end
  end

  private_constant :OperationBackends
end
