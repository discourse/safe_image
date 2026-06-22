# frozen_string_literal: true

require "tempfile"

module SafeImage
  # Inline implementations for local, read-only image metadata operations.
  class MetadataOperations < OperationSet
    def probe(path, max_pixels: nil)
      path = PathSafety.local_path(path)
      max_pixels = resolved_max_pixels(max_pixels)

      case File.extname(path).downcase
      when ".svg"
        info = SvgMetadata.probe(path, max_pixels: max_pixels)
        Result.metadata(
          input: File.expand_path(path),
          input_format: "svg",
          width: info.fetch(:width),
          height: info.fetch(:height),
          backend: :svg_metadata,
          duration_ms: info.fetch(:duration_ms)
        )
      when ".ico"
        # Pure-Ruby directory parse; reports the largest entry's dimensions.
        info = Ico.probe(path, max_pixels: max_pixels)
        Result.metadata(
          input: File.expand_path(path),
          input_format: "ico",
          width: info.fetch(:width),
          height: info.fetch(:height),
          backend: :ico_metadata,
          duration_ms: info.fetch(:duration_ms)
        )
      else
        case config.backend
        when :vips
          Processor.new(max_pixels: max_pixels, config: config).probe(path)
        when :imagemagick
          info = ImageMagickBackend.probe(path, max_pixels: max_pixels)
          Result.metadata(
            input: File.expand_path(path),
            input_format: info.fetch(:input_format),
            width: info.fetch(:width),
            height: info.fetch(:height),
            backend: :imagemagick,
            duration_ms: info.fetch(:duration_ms)
          )
        end
      end
    end

    def type(path, max_pixels: nil)
      fastimage_type(probe(path, max_pixels: max_pixels).input_format)
    end

    def size(path, max_pixels: nil)
      result = probe(path, max_pixels: max_pixels)
      [result.width, result.height]
    end

    def dimensions(path, max_pixels: nil)
      size(path, max_pixels: max_pixels)
    end

    def info(path, max_pixels: nil, animated: false, orientation: false)
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

    def orientation(path, max_pixels: nil)
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

    def dominant_color(path, max_pixels: nil)
      max_pixels = resolved_max_pixels(max_pixels)
      case config.backend
      when :vips
        if File.extname(PathSafety.local_path(path)).downcase == ".ico"
          # The configured backend is vips; ICO bytes are decoded by the
          # pure-Ruby parser and the extracted PNG is averaged by the vips helper.
          vips_ico_dominant_color(path, max_pixels: max_pixels)
        else
          VipsBackend.dominant_color(path, max_pixels: max_pixels)
        end
      when :imagemagick
        imagemagick_dominant_color(path, max_pixels: max_pixels)
      end
    end

    def frame_count(path, max_pixels: nil)
      backend.frame_count(path, max_pixels: max_pixels)
    end

    def animated?(path, max_pixels: nil)
      return false if File.extname(PathSafety.local_path(path)).downcase == ".svg"

      backend.frame_count(path, max_pixels: max_pixels).to_i > 1
    end

    def self.fastimage_type(format)
      format.to_s == "jpg" ? :jpeg : format.to_s.to_sym
    end

    private

    def vips_ico_dominant_color(path, max_pixels:)
      Tempfile.create(%w[safe-image-ico .png]) do |tmp|
        tmp.close
        Ico.convert_to_png(path, tmp.path, max_pixels: max_pixels)
        VipsBackend.dominant_color(tmp.path, max_pixels: max_pixels)
      end
    end

    def imagemagick_dominant_color(path, max_pixels:)
      # Probe first: rejects undecodable files and enforces the pixel cap before
      # ImageMagick fully decodes the image to average it.
      probe(path, max_pixels: max_pixels)
      ImageMagickBackend.dominant_color(path)
    end

    def fastimage_type(format)
      self.class.fastimage_type(format)
    end

    def backend
      OperationBackends.for(config)
    end
  end

  private_constant :MetadataOperations
end
