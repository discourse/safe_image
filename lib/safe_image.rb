# frozen_string_literal: true

require_relative "safe_image/version"

module SafeImage
  class Error < StandardError
    attr_reader :original_error_class, :stderr_tail

    def initialize(message = nil, original_error_class: nil, stderr_tail: nil)
      super(message)
      @original_error_class = original_error_class
      @stderr_tail = stderr_tail
    end
  end

  # Raised when any operation is attempted before SafeImage.configure!.
  class NotConfiguredError < Error
  end

  class UnsupportedFormatError < Error
  end

  # Raised when libvips cannot be loaded at runtime. configure!(backend: :vips)
  # surfaces this at boot; operations never fall back to ImageMagick.
  class VipsUnavailableError < UnsupportedFormatError
  end

  class UnsafePathError < Error
  end

  class InvalidImageError < Error
  end

  class LimitError < Error
  end

  # Default decompression-bomb ceiling when configure! is not given an explicit
  # max_pixels. Mirrored in the native binding (SAFE_IMAGE_DEFAULT_MAX_PIXELS)
  # and aligned with the 128MP area limit on the ImageMagick path. Per-call
  # max_pixels: overrides the configured value.
  DEFAULT_MAX_PIXELS = 128 * 1024 * 1024

  BACKENDS = %i[vips imagemagick].freeze

  # Process-wide configuration. configure! builds a frozen instance and swaps
  # it in with a single assignment, so readers never observe a half-applied
  # config.
  Config = Data.define(:backend, :landlock, :max_pixels)
end

require_relative "safe_image/native"
require_relative "safe_image/result"
require_relative "safe_image/quality_defaults"
require_relative "safe_image/runner"
require_relative "safe_image/path_safety"
require_relative "safe_image/formats"
require_relative "safe_image/backend_label"
require_relative "safe_image/operation_registry"
require_relative "safe_image/sandbox_protocol"
require_relative "safe_image/atomic_output"
require_relative "safe_image/sandbox"
require_relative "safe_image/native_helper"
require_relative "safe_image/optimizer"
require_relative "safe_image/svg_metadata"
require_relative "safe_image/remote"
require_relative "safe_image/ico"
require_relative "safe_image/image_magick_backend"
require_relative "safe_image/jpegli_backend"
require_relative "safe_image/vips_backend"
require_relative "safe_image/processor"
require_relative "safe_image/operation_backends"
require_relative "safe_image/operations"
require_relative "safe_image/api/metadata"
require_relative "safe_image/api/transform"

module SafeImage
  private_constant :Operations
  private_constant :API

  module_function

  @config = nil

  # Decides, in one place, everything that varies by host: which backend
  # decodes untrusted bytes, whether operations run inside the Landlock
  # sandbox, and the default decompression-bomb ceiling. Must be called before
  # any operation; calling it again replaces the configuration.
  #
  # Validation is eager so a misconfigured host fails at boot rather than on
  # the first request.
  def configure!(backend:, landlock:, max_pixels: DEFAULT_MAX_PIXELS)
    backend = backend.to_sym
    if BACKENDS.none? { |candidate| candidate == backend }
      raise ArgumentError, "unknown backend: #{backend.inspect} (expected :vips or :imagemagick)"
    end
    unless [true, false].any? { |candidate| candidate == landlock }
      raise ArgumentError, "landlock must be true or false, got: #{landlock.inspect}"
    end
    max_pixels = Integer(max_pixels)
    raise ArgumentError, "max_pixels must be positive" if max_pixels <= 0

    case backend
    when :vips
      begin
        VipsGlue.init!
      rescue VipsUnavailableError => e
        raise Error, "backend: :vips requested but libvips is unavailable: #{e.message}"
      end
    when :imagemagick
      unless Runner.available?("magick") || Runner.available?("convert")
        raise Error, "backend: :imagemagick requested but no magick/convert executable was found"
      end
    end
    if landlock && !Sandbox.available?
      raise Error, "landlock: true requested but the Landlock sandbox is unavailable on this host"
    end
    NativeHelper.ensure_available! if landlock && backend == :vips

    @config = Config.new(backend: backend, landlock: landlock, max_pixels: max_pixels)
  end

  def config
    @config ||
      raise(
        NotConfiguredError,
        "call SafeImage.configure!(backend: :vips | :imagemagick, landlock: true | false) before using SafeImage"
      )
  end

  def configured? = !@config.nil?

  def sandbox_available? = Sandbox.available?

  # Internal: whether operations must route through the sandbox worker. False
  # before configure! (so configure!'s own availability probes can run
  # commands) and inside worker children (so sandboxed operations never nest).
  def sandbox?
    !!@config&.landlock && ENV["SAFE_IMAGE_SANDBOX_CHILD"] != "1"
  end

  # Internal: per-call max_pixels overrides the configured default.
  def resolved_max_pixels(max_pixels, config: self.config)
    max_pixels.nil? ? config.max_pixels : max_pixels
  end

  def maybe_sandbox(operation, args: [], kwargs: {}, config: nil)
    config ||= self.config
    return yield unless sandbox?

    Sandbox.public_call!(operation, args: args, kwargs: kwargs, config: config)
  end

  extend API::Metadata
  extend API::Transform
end
