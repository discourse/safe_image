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
        raise UnsafePathError, "output path is a directory: #{path}" if File.directory?(path.to_s)
      end
      path
    end

    def ensure_distinct_file_paths!(input, output)
      input = ensure_regular_file!(input)
      output = ensure_safe_output_path!(output)
      same_path = input.to_s == output.to_s
      same_file = output.exist? && File.identical?(input.to_s, output.to_s)
      raise UnsafePathError, "input and output must be different paths" if same_path || same_file

      [input, output]
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
      # Expand to an absolute path first so callers may pass relative paths
      # (matching the rest of the public API), then apply the absolute-path and
      # safe-character checks to the resolved path.
      expanded = Pathname.new(local_path(path)).expand_path.to_s
      ensure_imagemagick_safe!(expanded)
      ensure_regular_file!(Pathname.new(expanded)).to_s
    end
  end
end
