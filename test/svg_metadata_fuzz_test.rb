# frozen_string_literal: true

require_relative "test_helper"

module SafeImage
  # Byte/structure-level fuzzing around the SVG metadata gate. The sanitizer's
  # DOM fuzz test starts from well-formed XML; this one deliberately includes
  # malformed XML, hostile declarations, unsafe encodings, NULs, and random byte
  # soup. The invariant is that untrusted SVG input is either accepted safely or
  # rejected inside SafeImage's error hierarchy — never with a raw parser/runtime
  # exception escaping to callers.
  class SvgMetadataFuzzTest < TestCase
    SVG_XMLNS = "http://www.w3.org/2000/svg"
    SEEDS = ENV.fetch("SAFE_IMAGE_FUZZ_SEEDS", "3,99,4096,90001").split(",").map { |seed| Integer(seed) }.freeze
    CASES_PER_SEED = Integer(ENV.fetch("SAFE_IMAGE_METADATA_FUZZ_CASES", ENV.fetch("SAFE_IMAGE_FUZZ_DOCUMENTS", "125")))

    TOKENS = [
      "<svg", "</svg>", "<g>", "</g>", "<rect", "/>", ">", "=", "'", '"', "&", "&xxe;",
      "<!DOCTYPE svg [ <!ENTITY xxe SYSTEM 'file:///etc/passwd'> ]>", "<?xml-stylesheet href='http://evil.example/x.css'?>",
      "xmlns='#{SVG_XMLNS}'", "width='10'", "height='10'", "viewBox='0 0 10 10'", "onload='alert(1)'",
      "href='javascript:alert(1)'", "fill='url(http://evil.example/x)'", "\x00", "\xC0\xAF".b,
      "\xEF\xBB\xBF".b, "\u202E"
    ].freeze

    def test_svg_metadata_and_sanitizer_reject_fuzz_inside_error_hierarchy
      SEEDS.each do |seed|
        rng = Random.new(seed)
        CASES_PER_SEED.times do |index|
          bytes = random_svg_bytes(rng)
          path = tmp_path("svg-metadata-fuzz-#{seed}-#{index}.svg")
          File.binwrite(path, bytes.b)

          assert_safe_size_result(path, bytes)
          assert_safe_sanitize_result(path, bytes)
        end
      end
    end

    private

    def assert_safe_size_result(path, bytes)
      result = SafeImage.size(path)
      assert_equal 2, result.length, "size result shape for #{bytes.inspect}"
      assert result.all? { |dimension| dimension.is_a?(Integer) && dimension.positive? },
             "non-positive dimensions #{result.inspect} for #{bytes.inspect}"
    rescue SafeImage::Error
      # Rejection is a safe outcome for arbitrary untrusted bytes.
    rescue StandardError => e
      flunk "raw #{e.class} escaped from SafeImage.size for #{bytes.inspect}: #{e.message}"
    end

    def assert_safe_sanitize_result(path, bytes)
      SafeImage.sanitize_svg!(path, id_namespace: "u1")
      cleaned = File.read(path)
      doc = REXML::Document.new(cleaned)
      assert_equal "svg", doc.root&.name, "sanitized non-svg root for #{bytes.inspect}"
      refute_match(/<!DOCTYPE|<\?(?!xml\s)|<script\b|<foreignObject\b/i, cleaned,
                   "unsafe markup survived sanitized fuzz case #{bytes.inspect}")
      walk(doc.root) do |node|
        node.attributes.each_attribute do |attr|
          refute attr.name.to_s.downcase.start_with?("on"),
                 "event attribute #{attr.expanded_name} survived sanitized fuzz case #{bytes.inspect}"
          refute_match(/(?:javascript|data):/i, attr.value.to_s,
                       "active URL survived in sanitized attribute #{attr.expanded_name} for #{bytes.inspect}")
        end
      end
    rescue SafeImage::Error
      # Rejection is a safe outcome for arbitrary untrusted bytes.
    rescue StandardError => e
      flunk "raw #{e.class} escaped from sanitize_svg! for #{bytes.inspect}: #{e.message}"
    end

    def walk(element, &block)
      yield element
      element.children.each { |child| walk(child, &block) if child.is_a?(REXML::Element) }
    end

    def random_svg_bytes(rng)
      case rng.rand(9)
      when 0
        validish_svg(rng)
      when 1
        malformed_svg(rng)
      when 2
        %(<?xml version="1.0" encoding="#{%w[UTF-16 Shift_JIS GBK UTF-7 windows-1252].sample(random: rng)}"?>\n) +
          validish_svg(rng)
      when 3
        "\xFF\xFE".b + validish_svg(rng).encode(Encoding::UTF_16LE).b
      when 4
        %(<!DOCTYPE svg [ <!ENTITY xxe SYSTEM "file:///etc/passwd"> ]>\n#{validish_svg(rng)})
      when 5
        %(<?xml version="1.0"?>\n<?xml-stylesheet href="http://evil.example/x.css"?>\n#{validish_svg(rng)})
      when 6
        random_token_soup(rng)
      when 7
        validish_svg(rng).bytes.insert(rng.rand(1..20), 0).pack("C*")
      else
        rng.bytes(rng.rand(0..128))
      end
    end

    def validish_svg(rng)
      attrs = [%(xmlns="#{SVG_XMLNS}"), width_attr(rng), height_attr(rng)].compact.join(" ")
      children = Array.new(rng.rand(0..5)) { child_snippet(rng) }.join
      %(<svg #{attrs}>#{children}</svg>)
    end

    def malformed_svg(rng)
      [
        "<svg><g",
        %(<svg xmlns="#{SVG_XMLNS}" width="10" height="10"><rect></svg></rect>),
        %(<svg xmlns="#{SVG_XMLNS}" width="&bad;" height="10"/>),
        %(<svg xmlns="#{SVG_XMLNS}" width="10" height="10"><![CDATA[unterminated),
        %(<html><body>nope</body></html>)
      ].sample(random: rng)
    end

    def random_token_soup(rng)
      Array.new(rng.rand(1..24)) { TOKENS.sample(random: rng).to_s.b }.join
    end

    def child_snippet(rng)
      case rng.rand(7)
      when 0 then %(<rect width="10" height="10" fill="url(#g)"/> )
      when 1 then %(<script>alert(1)</script>)
      when 2 then %(<g onload="alert(1)" y:onload="1" xmlns:y="#{SVG_XMLNS}"/>)
      when 3 then %(<style>.ok{fill:url(#g)} @import "//evil.example/x.css";</style>)
      when 4 then %(<text>#{xml_text(random_token_soup(rng))}</text>)
      when 5 then %(<s:rect xmlns:s="#{SVG_XMLNS}" fill="url(http://evil.example/x)"/> )
      else %(<foreignObject><html xmlns="http://www.w3.org/1999/xhtml"><script>x</script></html></foreignObject>)
      end
    end

    def width_attr(rng)
      ["width='10'", "width='0'", "width='1000000000'", "viewBox='0 0 10 10'", nil].sample(random: rng)
    end

    def height_attr(rng)
      ["height='10'", "height='-1'", "height='1000000000'", nil].sample(random: rng)
    end

    def xml_text(value)
      value.to_s.b.encode("UTF-8", invalid: :replace, undef: :replace).gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;")
    end
  end
end
