# frozen_string_literal: true

module SafeImage
  Info = Data.define(
    :path,
    :type,
    :width,
    :height,
    :size,
    :animated,
    :orientation
  )

  Result = Data.define(
    :input,
    :output,
    :input_format,
    :output_format,
    :width,
    :height,
    :filesize,
    :backend,
    :duration_ms,
    :optimizer
  ) do
    def success? = true
  end
end
