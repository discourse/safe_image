# frozen_string_literal: true

module SafeImage
  # Shared plumbing for public-operation implementations. Concrete operation
  # classes contain the inline implementation; child-process sandboxing happens
  # at the helper/command boundary, not by proxying these Ruby objects.
  class OperationSet
    attr_reader :config

    def initialize(config:)
      @config = config
    end

    private

    def resolved_max_pixels(max_pixels)
      SafeImage.resolved_max_pixels(max_pixels, config: config)
    end
  end

  private_constant :OperationSet
end
