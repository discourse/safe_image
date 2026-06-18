# frozen_string_literal: true

require_relative "test_helper"

module SafeImage
  class FormatAllowlistTest < TestCase
    C_HELPER = File.expand_path("../ext/safe_image_vips_helper/safe_image_vips_helper.c", __dir__)

    def test_ruby_and_c_native_format_allowlists_match
      source = File.read(C_HELPER)
      c_inputs =
        source.scan(/g_ascii_strcasecmp\(format, "([^"]+)"\)/).flatten.map { |fmt| Formats.native_canonical(fmt) }.uniq
      ruby_inputs = Formats::NATIVE_INPUTS.map { |fmt| Formats.native_canonical(fmt) }.uniq

      assert_equal ruby_inputs.sort, c_inputs.sort

      save_image = source[/static int save_image\(.*?^}/m]
      c_outputs = save_image.scan(/strcmp\(format, "([^"]+)"\)/).flatten.uniq
      ruby_outputs = Formats::NATIVE_OUTPUTS.map { |fmt| Formats.native_canonical(fmt) }.uniq

      assert_equal ruby_outputs.sort, c_outputs.sort
    end

    def test_ruby_and_c_quality_defaults_match
      source = File.read(C_HELPER)

      assert_equal QualityDefaults::JPEG, c_define(source, "DEFAULT_JPEG_QUALITY")
      assert_equal QualityDefaults::NATIVE_CONVERT_JPEG, c_define(source, "DEFAULT_NATIVE_CONVERT_JPEG_QUALITY")
    end

    private

    def c_define(source, name)
      match = source[/#define #{Regexp.escape(name)} (\d+)/, 1]
      raise "missing C define #{name}" unless match

      Integer(match)
    end
  end
end
