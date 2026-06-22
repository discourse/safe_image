# frozen_string_literal: true

require "fileutils"
require "pathname"
require "tempfile"

module SafeImage
  # Helpers for same-directory temporary outputs. External tools often require a
  # path, not an fd, so the helper intentionally creates and closes the tempfile
  # before yielding its path. The temp path is always next to the destination so
  # the final move stays on the same filesystem.
  module StagedOutput
    module_function

    def replace(output, suffix: nil)
      output_path = PathSafety.ensure_safe_output_path!(output)
      output_path.dirname.mkpath
      with_temp_path(output_path, suffix: suffix || output_path.extname) do |tmp_path|
        result = yield tmp_path, output_path
        FileUtils.mv(tmp_path, output_path)
        result
      end
    end

    def with_temp_path_near(output, suffix:)
      output_path = PathSafety.ensure_safe_output_path!(output)
      output_path.dirname.mkpath
      with_temp_path(output_path, suffix: suffix) { |tmp_path| yield tmp_path, output_path }
    end

    def with_temp_path(output_path, suffix:)
      Tempfile.create([output_path.basename(".*").to_s, suffix], output_path.dirname.to_s) do |tmp|
        tmp_path = Pathname.new(tmp.path)
        tmp.close
        yield tmp_path
      ensure
        FileUtils.rm_f(tmp_path) if defined?(tmp_path) && tmp_path
      end
    end
    private_class_method :with_temp_path
  end

  private_constant :StagedOutput
end
