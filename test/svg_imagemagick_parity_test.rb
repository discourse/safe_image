# frozen_string_literal: true

require "open3"
require_relative "test_helper"

module SafeImage
  # Numeric parity between this gem's non-rendering SVG probe and the
  # `identify -ping -format "%w %h" MSVG:` call it is meant to replace.
  #
  # The reference runs without the gem's bundled policy.xml on purpose: that
  # policy denies the SVG and MSVG coders outright, which is exactly why the
  # dimensions are read here instead of being delegated. The comparison is
  # therefore against an unrestricted ImageMagick — the thing callers are
  # migrating away from — so that migrating cannot silently change a dimension.
  class SvgImageMagickParityTest < TestCase
    # Documents both readers must agree on. Anything MSVG rejects (a negative,
    # zero, or unresolvable dimension with no viewBox to fall back on) must be
    # rejected here too, and is covered by the :reject expectation.
    CASES = {
      "plain" => %(width="120" height="80"),
      "px" => %(width="120px" height="80px"),
      "inches" => %(width="1.2in" height="0.9in"),
      "centimetres" => %(width="1cm" height="2cm"),
      "millimetres" => %(width="10mm" height="20mm"),
      "picas" => %(width="1pc" height="2pc"),
      "points" => %(width="120pt" height="80pt"),
      "unknown_unit" => %(width="120foo" height="80q"),
      "uppercase_unit" => %(width="120PX" height="80In"),
      "exponent" => %(width="1.2e2" height=".8e2"),
      "signed" => %(width="+120" height="+80"),
      "fractional" => %(width="120.4" height="80.6"),
      "half" => %(width="120.5" height="80.5"),
      "spaced_unit" => %(width="120 px" height="80 px"),
      "viewbox_only" => %(viewBox="0 0 300 150"),
      "viewbox_fractional" => %(viewBox="0 0 300.7 150.2"),
      "viewbox_offset" => %(viewBox="10 20 300 150"),
      "viewbox_exponent" => %(viewBox="0 0 1e2 5e1"),
      "width_only_viewbox" => %(width="600" viewBox="0 0 300 150"),
      "percent_viewbox" => %(width="100%" height="100%" viewBox="0 0 300 150"),
      "em_viewbox" => %(width="10em" height="10em" viewBox="0 0 300 150"),
      "zero_viewbox" => %(width="0" height="0" viewBox="0 0 120 90"),
      "zero_inches_viewbox" => %(width="0.0in" height="0.0in" viewBox="0 0 120 90"),
      "no_dimensions" => "",
      "percent_only" => %(width="100%" height="50%"),
      "negative" => %(width="-120" height="-80"),
      "zero" => %(width="0" height="0")
    }.freeze

    DOCTYPE = %(<!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd">)

    def setup
      super
      skip "identify is not available" unless Runner.available?("identify")
    end

    def test_dimensions_match_imagemagick
      mismatches =
        CASES.filter_map do |name, attributes|
          path = write_svg("#{name}.svg", attributes)
          expected = identify(path)
          actual = probe_dimensions(path)
          "#{name}: identify=#{expected.inspect} safe_image=#{actual.inspect}" unless expected == actual
        end

      assert_empty mismatches, "SVG dimensions diverged from identify MSVG:"
    end

    # The routine authoring-tool header must not change the answer, in either
    # reader. Without this the whole corpus above would still pass while every
    # real Illustrator or Inkscape export silently lost its dimensions.
    def test_dimensions_match_imagemagick_with_a_doctype
      mismatches =
        CASES.filter_map do |name, attributes|
          path = write_svg("doctype-#{name}.svg", attributes, prologue: DOCTYPE)
          expected = identify(path)
          actual = probe_dimensions(path)
          "#{name}: identify=#{expected.inspect} safe_image=#{actual.inspect}" unless expected == actual
        end

      assert_empty mismatches, "SVG dimensions with a DOCTYPE diverged from identify MSVG:"
    end

    private

    def write_svg(name, attributes, prologue: nil)
      write_tmp(name, [prologue, %(<svg xmlns="http://www.w3.org/2000/svg" #{attributes}></svg>)].compact.join("\n"))
    end

    # :reject stands for "this document has no usable dimensions", which MSVG
    # reports as a failed command and SafeImage reports as an error.
    def identify(path)
      stdout, _stderr, status = Open3.capture3("identify", "-ping", "-format", "%w %h", "MSVG:#{path}")
      return :reject unless status.success?

      stdout.split(" ").map { |value| Integer(value) }
    end

    def probe_dimensions(path)
      SafeImage.size(path)
    rescue Error
      :reject
    end
  end
end
