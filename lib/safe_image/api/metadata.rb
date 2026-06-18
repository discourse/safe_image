# frozen_string_literal: true

module SafeImage
  module API
    # Public read-only metadata operations. Methods stay exposed on SafeImage via
    # `extend`, while backend dispatch and sandbox details remain private.
    module Metadata
      def probe(path, max_pixels: nil)
        maybe_sandbox(:probe, args: [path], kwargs: { max_pixels: max_pixels }) do
          path = PathSafety.local_path(path)
          max_pixels = resolved_max_pixels(max_pixels)

          case File.extname(path).downcase
          when ".svg"
            info = SvgMetadata.probe(path, max_pixels: max_pixels)
            Result.new(
              input: File.expand_path(path),
              output: nil,
              input_format: "svg",
              output_format: nil,
              width: info.fetch(:width),
              height: info.fetch(:height),
              filesize: File.size(path),
              backend: "svg-metadata",
              duration_ms: info.fetch(:duration_ms),
              optimizer: nil
            )
          when ".ico"
            # Pure-Ruby directory parse; reports the largest entry's dimensions.
            info = Ico.probe(path, max_pixels: max_pixels)
            Result.new(
              input: File.expand_path(path),
              output: nil,
              input_format: "ico",
              output_format: nil,
              width: info.fetch(:width),
              height: info.fetch(:height),
              filesize: File.size(path),
              backend: "ico-metadata",
              duration_ms: info.fetch(:duration_ms),
              optimizer: nil
            )
          else
            case config.backend
            when :vips
              Processor.new(max_pixels: max_pixels).probe(path)
            when :imagemagick
              info = ImageMagickBackend.probe(path, max_pixels: max_pixels)
              Result.new(
                input: File.expand_path(path),
                output: nil,
                input_format: info.fetch(:input_format),
                output_format: nil,
                width: info.fetch(:width),
                height: info.fetch(:height),
                filesize: File.size(path),
                backend: BackendLabel.build(:imagemagick),
                duration_ms: info.fetch(:duration_ms),
                optimizer: nil
              )
            end
          end
        end
      end

      def type(path, max_pixels: nil)
        maybe_sandbox(:type, args: [path], kwargs: { max_pixels: max_pixels }) do
          fastimage_type(probe(path, max_pixels: max_pixels).input_format)
        end
      end

      def size(path, max_pixels: nil)
        maybe_sandbox(:size, args: [path], kwargs: { max_pixels: max_pixels }) do
          result = probe(path, max_pixels: max_pixels)
          [result.width, result.height]
        end
      end

      def dimensions(path, max_pixels: nil)
        size(path, max_pixels: max_pixels)
      end

      def info(path, max_pixels: nil, animated: false, orientation: false)
        maybe_sandbox(
          :info,
          args: [path],
          kwargs: {
            max_pixels: max_pixels,
            animated: animated,
            orientation: orientation
          }
        ) do
          result = probe(path, max_pixels: max_pixels)
          type = fastimage_type(result.input_format)
          Info.new(
            path: result.input,
            type: type,
            width: result.width,
            height: result.height,
            size: [result.width, result.height],
            animated: animated ? animated?(path, max_pixels: max_pixels) : nil,
            orientation: orientation ? orientation(path, max_pixels: max_pixels) : nil
          )
        end
      end

      def orientation(path, max_pixels: nil)
        maybe_sandbox(:orientation, args: [path], kwargs: { max_pixels: max_pixels }) do
          case File.extname(PathSafety.local_path(path)).downcase
          when ".svg", ".ico"
            # No EXIF orientation in either format; upright by definition.
            1
          else
            max_pixels = resolved_max_pixels(max_pixels)
            case config.backend
            when :vips
              # Header-only native read.
              VipsBackend.orientation(path, max_pixels: max_pixels)
            when :imagemagick
              # Probe first: rejects undecodable files and enforces the pixel cap.
              ImageMagickBackend.probe(path, max_pixels: max_pixels)
              ImageMagickBackend.orientation(path)
            end
          end
        end
      end

      def dominant_color(path, max_pixels: nil)
        maybe_sandbox(:dominant_color, args: [path], kwargs: { max_pixels: max_pixels }) do
          max_pixels = resolved_max_pixels(max_pixels)
          case config.backend
          when :vips
            if File.extname(PathSafety.local_path(path)).downcase == ".ico"
              # Pure-Ruby ICO decode; vips only averages the decoded pixels.
              Ico.dominant_color(path, max_pixels: max_pixels)
            else
              VipsBackend.dominant_color(path, max_pixels: max_pixels)
            end
          when :imagemagick
            imagemagick_dominant_color(path, max_pixels: max_pixels)
          end
        end
      end

      def imagemagick_dominant_color(path, max_pixels:)
        # Probe first: rejects undecodable files and enforces the pixel cap before
        # ImageMagick fully decodes the image to average it.
        probe(path, max_pixels: max_pixels)
        ImageMagickBackend.dominant_color(path)
      end

      def fastimage_type(format)
        format.to_s == "jpg" ? :jpeg : format.to_s.to_sym
      end

      def remote_info(url, **kwargs)
        config
        Remote.info(url, **kwargs)
      end

      def remote_size(url, **kwargs)
        config
        Remote.size(url, **kwargs)
      end

      def remote_dimensions(url, **kwargs)
        remote_size(url, **kwargs)
      end

      def remote_type(url, **kwargs)
        config
        Remote.type(url, **kwargs)
      end

      def remote_animated?(url, **kwargs)
        config
        Remote.animated?(url, **kwargs)
      end

      def remote_dominant_color(url, **kwargs)
        config
        Remote.dominant_color(url, **kwargs)
      end

      def fetch_remote(url, **kwargs, &block)
        config
        Remote.fetch(url, **kwargs, &block)
      end

      def frame_count(path, max_pixels: nil)
        maybe_sandbox(:frame_count, args: [path], kwargs: { max_pixels: max_pixels }) do
          Operations.frame_count(path, max_pixels: max_pixels)
        end
      end

      def animated?(path, max_pixels: nil)
        config
        return false if File.extname(PathSafety.local_path(path)).downcase == ".svg"

        maybe_sandbox(:animated?, args: [path], kwargs: { max_pixels: max_pixels }) do
          Operations.animated?(path, max_pixels: max_pixels)
        end
      end

      private :imagemagick_dominant_color, :fastimage_type
    end
  end
end
