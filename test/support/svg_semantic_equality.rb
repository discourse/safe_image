# frozen_string_literal: true

require "rexml/document"

module SafeImage
  # Semantic equality for two serialized SVG documents, used by the parser
  # migration's differential tests. REXML and Nokogiri serialize the same tree
  # with different attribute ordering, quote characters, namespace-prefix
  # spelling, and inter-element whitespace, so a byte comparison would report
  # spurious differences. This canonicalises both sides to the only things that
  # are security-relevant — element identity (namespace URI + local name),
  # the set of attributes (namespace URI + local name + value), text content,
  # and child order — and compares those.
  #
  # It deliberately parses with REXML (a neutral third parser, not either
  # backend under test) so the comparison cannot inherit a quirk of the very
  # backend it is meant to check. The canonical form is a plain nested Array/
  # Hash structure, so a mismatch pretty-prints to an obvious diff.
  module SvgSemanticEquality
    module_function

    SVG_NS = "http://www.w3.org/2000/svg"
    XLINK_NS = "http://www.w3.org/1999/xlink"

    # Returns true when the two serialized documents are semantically equal.
    def equal?(a, b)
      canonical(a) == canonical(b)
    end

    # The canonical form, exposed so a failing assertion can show both sides.
    def canonical(xml)
      doc = REXML::Document.new(xml)
      raise ArgumentError, "no root in #{xml.inspect}" unless doc.root

      canonical_element(doc.root)
    end

    def canonical_element(element)
      {
        name: expanded_name(element),
        attrs: canonical_attributes(element),
        children: element.children.filter_map { |child| canonical_child(child) }
      }
    end

    # Attributes keyed by [namespace-uri, local-name] so prefix spelling does not
    # matter, but a real namespace difference (e.g. plain href vs xlink:href)
    # still does. xmlns / xmlns:* declarations are folded into a normalised set
    # of in-scope (prefix-independent) namespace URIs, because the security
    # property is "which namespaces are declared", not their prefix spelling.
    def canonical_attributes(element)
      attrs = {}
      namespaces = []
      element.attributes.each_attribute do |attr|
        if attr.expanded_name == "xmlns" || attr.prefix == "xmlns"
          namespaces << attr.value.to_s
        else
          attrs[[attr.namespace.to_s, attr.name.to_s]] = attr.value.to_s
        end
      end
      { values: attrs, namespaces: namespaces.sort.uniq }
    end

    def canonical_child(node)
      case node
      when REXML::Element
        canonical_element(node)
      when REXML::Text
        text = node.to_s
        text.strip.empty? ? nil : [:text, text]
      when REXML::CData
        [:cdata, node.value.to_s]
      end
    end

    def expanded_name(element)
      [element.namespace.to_s, element.name.to_s]
    end
  end
end
