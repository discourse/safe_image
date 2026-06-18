# frozen_string_literal: true

module SafeImage
  # Public metadata return value. Optional fields (`animated`, `orientation`) are
  # nil unless the caller opts into the extra probes.
  Info = Data.define(:path, :type, :width, :height, :size, :animated, :orientation)

  # Public image-operation return value. `output`/`output_format` are nil for
  # metadata-only probes; image-producing operations always include them.
  Result =
    Data.define(
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
    ) { def success? = true }
end
