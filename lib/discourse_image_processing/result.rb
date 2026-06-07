# frozen_string_literal: true

module DiscourseImageProcessing
  Result = Data.define(
    :input,
    :output,
    :input_format,
    :output_format,
    :width,
    :height,
    :filesize,
    :backend,
    :duration_ms
  ) do
    def success? = true
  end
end
