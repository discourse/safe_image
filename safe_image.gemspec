# frozen_string_literal: true

require_relative "lib/safe_image/version"

Gem::Specification.new do |spec|
  spec.name = "safe_image"
  spec.version = SafeImage::VERSION
  spec.summary = "Hardened image processing boundary for untrusted uploads"
  spec.description =
    "Safe Image is a small Ruby image-processing boundary for untrusted uploads: direct libvips thumbnails/probing, hardened ImageMagick compatibility operations, optimisation, SVG metadata probing, and optional atomic Landlock sandbox execution."
  spec.homepage = "https://github.com/sam-saffron-jarvis/safe-image"
  spec.license = "MIT"
  spec.authors = ["Sam Saffron", "Jarvis"]
  spec.email = ["sam@discourse.org"]
  spec.required_ruby_version = ">= 3.1"

  # Explicit allowlist of shipped files.
  spec.files =
    Dir[
      "lib/**/*.rb",
      "lib/safe_image/RT_sRGB.icm",
      "lib/safe_image/imagemagick_policy/policy.xml",
      "lib/safe_image/fonts/DejaVuSans.ttf",
      "lib/safe_image/fonts/DEJAVU-LICENSE",
      "ext/safe_image_vips_helper/extconf.rb",
      "ext/safe_image_vips_helper/safe_image_vips_helper.c",
      "LICENSE",
      "README.md",
      "SECURITY.md",
      "CHANGELOG.md",
      "docs/**/*.md"
    ]
  spec.require_paths = ["lib"]
  spec.extensions = ["ext/safe_image_vips_helper/extconf.rb"]

  # libvips is bound at runtime through Fiddle (stdlib today, a bundled gem
  # from Ruby 3.5); nothing compiles at install time.
  spec.add_runtime_dependency "fiddle", ">= 1.0"
  # SVG metadata uses Nokogiri's SAX parser, loaded lazily on first SVG use.
  spec.add_runtime_dependency "nokogiri", "~> 1.16"

  spec.add_development_dependency "minitest", "~> 5.25"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rubocop-discourse", "~> 3.18"
  spec.add_development_dependency "syntax_tree", "~> 6.3"
  # Exercises the Landlock sandbox tests (they skip when unavailable);
  # intentionally NOT a runtime dependency — see README.
  spec.add_development_dependency "landlock", ">= 0.3"

  spec.metadata = {
    "homepage_uri" => spec.homepage,
    "source_code_uri" => spec.homepage,
    "rubygems_mfa_required" => "true"
  }
end
