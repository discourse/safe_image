# frozen_string_literal: true

module SafeImage
  # Public metadata return value. Optional fields (`animated`, `orientation`) are
  # nil unless the caller opts into the extra probes.
  Info = Data.define(:path, :type, :width, :height, :size, :animated, :orientation)

  # Public image-operation return value. `output`/`output_format` are nil for
  # metadata-only probes; image-producing operations always include them. `tier`
  # records the concrete execution tier (for example :native_encode,
  # :jpegtran_lossless or :jpegtran_fallback_reencode) so non-fatal degradation
  # is observable without parsing the backend label.
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
      :optimizer,
      :tier
    ) do
      def self.build(
        input:,
        output: nil,
        input_format:,
        output_format: nil,
        width:,
        height:,
        backend:,
        duration_ms:,
        filesize: nil,
        optimizer: nil,
        encoder: nil,
        tier: nil
      )
        new(
          input: input.to_s,
          output: output&.to_s,
          input_format: input_format,
          output_format: output_format,
          width: width,
          height: height,
          filesize: filesize || result_filesize(input, output),
          backend: BackendLabel.build(backend, encoder: encoder),
          duration_ms: duration_ms,
          optimizer: optimizer,
          tier: tier
        )
      end

      def self.metadata(input:, input_format:, width:, height:, backend:, duration_ms:)
        build(
          input: input,
          input_format: input_format,
          width: width,
          height: height,
          filesize: File.size(input),
          backend: backend,
          duration_ms: duration_ms,
          tier: :metadata
        )
      end

      def self.result_filesize(input, output)
        path = output || input
        path ? File.size(path) : nil
      end

      def success? = true
    end
end
