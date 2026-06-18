# frozen_string_literal: true

require "pathname"

module SafeImage
  module OperationBackends
    # Shared operation-strategy plumbing: path normalization, max-pixel config,
    # optimizer post-processing and uniform Result construction.
    class Base
      attr_reader :config

      def initialize(config:)
        @config = config
      end

      def frame_count(path, max_pixels: nil)
        max_pixels = resolved_max_pixels(max_pixels)
        # ico directories are counted by the pure-Ruby parser on either backend;
        # everything else is a header-only count.
        if File.extname(PathSafety.local_path(path)).downcase == ".ico"
          return Ico.frame_count(path, max_pixels: max_pixels)
        end

        backend_frame_count(path, max_pixels: max_pixels)
      end

      private

      def input_output!(input, output)
        input, output = PathSafety.ensure_distinct_file_paths!(input, output)
        [input.to_s, output.to_s]
      end

      def safe_output!(output)
        PathSafety.ensure_safe_output_path!(output).to_s
      end

      def resolved_max_pixels(max_pixels)
        SafeImage.resolved_max_pixels(max_pixels, config: config)
      end

      # Post-processing applies only to the formats the optimizer tools
      # understand; other outputs (gif, jxl, ...) skip the pass.
      def optimize_output(output, quality)
        format = Formats.extension(output)
        return unless Formats.optimizable_output?(format)

        write_through_tempfile(output) do |tmp_path|
          Optimizer.optimize(
            input: output,
            output: tmp_path,
            mode: :lossless,
            strip_metadata: true,
            quality: quality,
            assume_upright: true
          )
        end
      end

      # Writes via a sibling tempfile and renames into place so callers never
      # observe a partially-written destination.
      def write_through_tempfile(output)
        AtomicOutput.replace(output, suffix: ".safe-image#{File.extname(output)}") { |tmp_path| yield tmp_path }
      end

      def result_from_info(input, output, info, backend, tier: nil, optimizer: nil)
        Result.build(
          input: input,
          output: output,
          input_format: info.fetch(:input_format),
          output_format: info.fetch(:output_format),
          width: info.fetch(:width),
          height: info.fetch(:height),
          backend: backend,
          encoder: info[:encoder],
          duration_ms: info.fetch(:duration_ms),
          optimizer: optimizer,
          tier: tier
        )
      end
    end
  end
end
