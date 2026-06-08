# frozen_string_literal: true

require "pathname"

module SafeImage
  module PathSafety
    SAFE_IMAGEMAGICK_PATH = %r{\A[\w\-\./]+\z}.freeze

    module_function

    def local_path(value)
      if value.respond_to?(:path) && value.path
        value.path.to_s
      else
        value.to_s
      end
    end

    def reject_symlink_components!(path)
      path = Pathname.new(local_path(path)).expand_path
      path.ascend do |component|
        next unless File.exist?(component.to_s)
        raise UnsafePathError, "symlink paths are not allowed: #{component}" if File.lstat(component.to_s).symlink?
      end
      path
    end

    def ensure_regular_file!(path)
      path = reject_symlink_components!(path)
      raise UnsafePathError, "not a file: #{path}" unless path.file?
      path
    end

    def ensure_safe_output_path!(path)
      path = Pathname.new(local_path(path)).expand_path
      raise UnsafePathError, "path contains NUL" if path.to_s.include?("\0")
      reject_symlink_components!(path.dirname)
      if File.exist?(path.to_s)
        raise UnsafePathError, "output path is a symlink: #{path}" if File.lstat(path.to_s).symlink?
      end
      path
    end

    def ensure_imagemagick_safe!(path)
      path = local_path(path)
      raise UnsafePathError, "path contains NUL" if path.include?("\0")
      raise UnsafePathError, "path must be absolute" unless path.start_with?("/")
      unless SAFE_IMAGEMAGICK_PATH.match?(path)
        raise UnsafePathError, "path contains characters unsafe for ImageMagick pseudo-filename parsing"
      end
      path
    end

    def ensure_imagemagick_input_file!(path)
      path = Pathname.new(ensure_imagemagick_safe!(path)).expand_path
      ensure_regular_file!(path).to_s
    end
  end
end
