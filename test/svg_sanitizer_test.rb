# frozen_string_literal: true

require_relative "test_helper"

module SafeImage
  class SvgSanitizerTest < TestCase
    def test_rejects_non_svg_root
      path = write_tmp("not.svg", "<html><body>nope</body></html>")
      assert_raises(InvalidImageError) { SafeImage.sanitize_svg!(path) }
    end

    def test_strips_active_content_and_keeps_fragment_references
      path = write_tmp("bad.svg", <<~SVG)
        <svg xmlns="http://www.w3.org/2000/svg" width="10" height="10" onload="alert(1)">
          <script>alert(1)</script>
          <style>@import url(http://evil.example/x.css); rect { fill: red; }</style>
          <foreignObject><iframe srcdoc="&lt;script&gt;alert(1)&lt;/script&gt;"></iframe></foreignObject>
          <image href="http://evil.example/track.png"/>
          <animate attributeName="x" from="0" to="10"/>
          <rect width="10" height="10" fill="url(http://evil.example/x)" onclick="alert(1)" onmouseover="alert(1)"/>
          <a href="javascript:alert(1)"><text>bad</text></a>
          <use href="#safe"/>
          <circle id="safe" r="2" fill="url(#safe)"/>
          <!-- <script>alert(1)</script> -->
          <text><![CDATA[<script>alert(1)</script>&xss;]]></text>
        </svg>
      SVG

      SafeImage.sanitize_svg!(path)
      cleaned = File.read(path)

      refute_match(/<script/i, cleaned, "kept script element")
      refute_match(/<style/i, cleaned, "kept style element")
      refute_match(/foreignObject/i, cleaned, "kept foreignObject")
      refute_match(/<(?:iframe|object|embed|image)\b/i, cleaned, "kept embedded content element")
      refute_match(/<animate/i, cleaned, "kept animation")
      refute_includes cleaned, "evil.example", "kept external URL"
      refute_includes cleaned, "onload", "kept onload handler"
      refute_includes cleaned, "onclick", "kept onclick handler"
      refute_includes cleaned, "onmouseover", "kept onmouseover handler"
      refute_match(/javascript/i, cleaned, "kept javascript href")
      refute_includes cleaned, "<!--", "kept comment"
      refute_includes cleaned, "CDATA", "kept CDATA section"

      assert cleaned.include?("href='#safe'") || cleaned.include?('href="#safe"'), "stripped fragment href"
      assert_includes cleaned, "url(#safe)", "stripped fragment url"
      assert_includes cleaned, "&lt;script&gt;", "failed to escape text content"
      assert_includes cleaned, "&amp;xss;", "failed to escape entity in text"
    end

    def test_strips_entity_encoded_external_urls
      path = write_tmp("encoded-url.svg", <<~SVG)
        <svg xmlns="http://www.w3.org/2000/svg" width="10" height="10">
          <rect width="10" height="10" fill="url(&#104;ttp://evil.example/x)"/>
          <a href="jav&#x61;script:alert(1)"><text>bad</text></a>
        </svg>
      SVG

      SafeImage.sanitize_svg!(path)
      cleaned = File.read(path)

      refute_includes cleaned, "evil.example", "kept entity-encoded URL"
      refute_match(/javascript/i, cleaned, "kept entity-encoded javascript")
    end

    def test_rejects_dtd_entity_payloads
      path = write_tmp("dtd-entity.svg", <<~SVG)
        <?xml version="1.0"?>
        <!DOCTYPE svg [ <!ENTITY xss "<script>alert(1)</script>"> ]>
        <svg xmlns="http://www.w3.org/2000/svg" width="10" height="10">
          <text>&xss;</text>
        </svg>
      SVG

      assert_raises(InvalidImageError) { SafeImage.sanitize_svg!(path) }
    end

    def test_rejects_huge_dimensions
      path = write_tmp("huge.svg", '<svg xmlns="http://www.w3.org/2000/svg" width="100000" height="100000"></svg>')
      assert_raises(LimitError) { SafeImage.sanitize_svg!(path) }
    end
  end
end
