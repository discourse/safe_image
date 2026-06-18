# frozen_string_literal: true

module SafeImage
  module BackendLabel
    module_function

    BASE = { vips: "libvips-direct", imagemagick: "imagemagick" }.freeze

    def build(backend, encoder: nil)
      base = BASE.fetch(backend.to_sym)
      encoder.to_s == "cjpegli" ? "#{base}+cjpegli" : base
    end
  end

  private_constant :BackendLabel
end
