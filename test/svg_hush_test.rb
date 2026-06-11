# frozen_string_literal: true

require_relative "test_helper"

module SafeImage
  # Standalone SVG sanitisation via the bundled svg-hush binary. These exercise
  # the real binary directly (no backend/landlock needed), and skip cleanly on a
  # platform we don't ship a binary for.
  class SvgHushTest < TestCase
    def setup
      super
      skip("no bundled svg-hush binary for #{SvgHush.platform_slug}") unless bundled_binary?
    end

    def test_neutralises_namespace_prefixed_onload_xss
      # The Finding-4 payload: <x:svg> (x bound to the SVG ns) is a real svg, and
      # a bare null-namespace onload would execute. svg-hush must strip it.
      svg = write_svg("xss.svg", <<~SVG)
        <svg xmlns="http://www.w3.org/2000/svg" xmlns:x="http://www.w3.org/2000/svg" xmlns:y="http://www.w3.org/2000/svg" width="10" height="10">
          <x:svg onload="alert(document.domain)" y:onload="1"/>
        </svg>
      SVG

      SvgHush.sanitize!(svg)
      cleaned = File.read(svg)
      refute_match(/onload/i, cleaned, "event handler survived")
      refute_match(/alert/i, cleaned, "script payload survived")
    end

    def test_strips_scripts_and_handlers
      svg = write_svg("active.svg", %q{<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10" onload="x"><script>evil()</script><rect width="10" height="10" onclick="x"/></svg>})
      SvgHush.sanitize!(svg)
      refute_match(/script|onload|onclick/i, File.read(svg))
    end

    def test_keeps_benign_drawing
      svg = write_svg("ok.svg", <<~SVG)
        <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20">
          <defs><linearGradient id="g"><stop offset="0" stop-color="#f00"/></linearGradient></defs>
          <style>rect{fill:red}</style>
          <rect width="20" height="20" fill="url(#g)"/>
        </svg>
      SVG
      result = SvgHush.sanitize!(svg)
      assert_equal "svg", result[:format]
      cleaned = File.read(svg)
      assert_match(/<rect/, cleaned)
      assert_match(/linearGradient/, cleaned)
      assert_match(/url\(#g\)/, cleaned)
    end

    def test_returns_result_shape
      svg = write_svg("shape.svg", %q{<svg xmlns="http://www.w3.org/2000/svg" width="5" height="5"><rect width="5" height="5"/></svg>})
      result = SvgHush.sanitize!(svg)
      assert_equal({ format: "svg", sanitized: true, filesize: File.size(svg) }, result)
    end

    def test_rejects_oversized_dimensions
      svg = write_svg("huge.svg", %q{<svg xmlns="http://www.w3.org/2000/svg" width="999999" height="999999"><rect width="1" height="1"/></svg>})
      assert_raises(LimitError) { SvgHush.sanitize!(svg) }
    end

    def test_honours_max_pixels
      svg = write_svg("px.svg", %q{<svg xmlns="http://www.w3.org/2000/svg" width="50" height="50"><rect/></svg>})
      assert_raises(LimitError) { SvgHush.sanitize!(svg, max_pixels: 100) }
    end

    def test_rejects_doctype
      svg = write_svg("dtd.svg", %q{<!DOCTYPE svg [<!ENTITY x "y">]><svg xmlns="http://www.w3.org/2000/svg" width="5" height="5"><rect/></svg>})
      assert_raises(InvalidImageError) { SvgHush.sanitize!(svg) }
    end

    def test_rejects_unsafe_encoding
      svg = write_svg("u16.svg", %q{<?xml version="1.0" encoding="utf-16"?><svg xmlns="http://www.w3.org/2000/svg" width="5" height="5"><rect/></svg>})
      assert_raises(InvalidImageError) { SvgHush.sanitize!(svg) }
    end

    def test_rejects_malformed_xml
      svg = write_svg("bad.svg", "<svg><unclosed")
      assert_raises(InvalidImageError) { SvgHush.sanitize!(svg) }
    end

    private

    def bundled_binary?
      SvgHush.binary
      true
    rescue Error
      false
    end

    def write_svg(name, content)
      path = tmp_path(name)
      File.write(path, content)
      path
    end
  end
end
