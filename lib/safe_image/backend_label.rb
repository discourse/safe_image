# frozen_string_literal: true

module SafeImage
  module BackendLabel
    module_function

    BASE = {
      vips: "libvips-direct",
      imagemagick: "imagemagick",
      vips_helper: "libvips-helper",
      svg_metadata: "svg-metadata",
      ico_metadata: "ico-metadata",
      ico_vips: "ico-ruby+libvips",
      jpegtran: "jpegtran"
    }.freeze

    def build(backend, encoder: nil)
      base = BASE.fetch(backend.to_sym)
      encoder.to_s == "cjpegli" ? "#{base}+cjpegli" : base
    end
  end

  private_constant :BackendLabel
end
