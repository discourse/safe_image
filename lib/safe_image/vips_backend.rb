# frozen_string_literal: true

module SafeImage
  module VipsBackend
    module_function

    DIMENSIONS_RE = /\A(?:(?<percent>\d+(?:\.\d+)?)%|(?<w>\d*)x(?<h>\d*)(?<only_down>>)?|(?<pixels>\d+)@)\z/

    def crop_north(input:, output:, width:, height:, format:, quality: 85, max_pixels: nil)
      Native.crop_north(input.to_s, output.to_s, Integer(width), Integer(height), format.to_s, Integer(quality), max_pixels)
    end

    def downsize(input:, output:, dimensions:, format:, quality: 85, max_pixels: nil)
      probe = SafeImage.probe(input, max_pixels: max_pixels)
      scale = scale_for(probe.width, probe.height, dimensions)
      # Never upscale, but always re-encode through the native saver — even on a
      # no-op scale of 1.0 — so the output is metadata-stripped rather than a
      # verbatim copy of the untrusted input bytes.
      scale = [scale, 1.0].min
      Native.resize(input.to_s, output.to_s, scale, normalized_format(format), Integer(quality), max_pixels)
    end

    def normalized_format(format)
      format = format.to_s.downcase
      format == "jpeg" ? "jpg" : format
    end

    def scale_for(width, height, dimensions)
      dimensions = dimensions.to_s
      match = DIMENSIONS_RE.match(dimensions) or raise ArgumentError, "unsupported dimensions: #{dimensions.inspect}"

      if match[:percent]
        return Float(match[:percent]) / 100.0
      end

      if match[:pixels]
        target_pixels = Float(match[:pixels])
        return Math.sqrt(target_pixels / (Integer(width) * Integer(height)))
      end

      target_w = match[:w].to_s.empty? ? nil : Float(match[:w])
      target_h = match[:h].to_s.empty? ? nil : Float(match[:h])
      scales = []
      scales << target_w / width if target_w
      scales << target_h / height if target_h
      raise ArgumentError, "missing width/height in dimensions: #{dimensions.inspect}" if scales.empty?
      scales.min
    end
  end
end
