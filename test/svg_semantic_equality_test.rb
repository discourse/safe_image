# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/svg_semantic_equality"

module SafeImage
  # Self-verification for the differential-migration oracle. The oracle is only
  # trustworthy if it (a) treats cosmetic serialization differences as equal and
  # (b) treats every security-relevant difference as unequal. If this drifts
  # toward "everything is equal", the parser-migration differential tests would
  # silently stop catching divergences, so these cases guard both directions.
  class SvgSemanticEqualityTest < TestCase
    E = SvgSemanticEquality
    NS = "http://www.w3.org/2000/svg"
    XLINK = "http://www.w3.org/1999/xlink"

    # --- must be treated as EQUAL (cosmetic only) ---

    def test_attribute_order_is_ignored
      assert E.equal?(
        %(<svg xmlns="#{NS}" width="10" height="20"><rect x="1" y="2"/></svg>),
        %(<svg xmlns="#{NS}" height="20" width="10"><rect y="2" x="1"/></svg>)
      )
    end

    def test_quote_style_and_inter_element_whitespace_ignored
      assert E.equal?(
        %(<svg xmlns="#{NS}"><g><rect x="1"/></g></svg>),
        %(<svg xmlns='#{NS}'>\n  <g>\n    <rect x='1'/>\n  </g>\n</svg>)
      )
    end

    def test_namespace_prefix_spelling_ignored
      assert E.equal?(
        %(<svg xmlns="#{NS}" xmlns:xlink="#{XLINK}"><use xlink:href="#a"/></svg>),
        %(<svg xmlns="#{NS}" xmlns:xl="#{XLINK}"><use xl:href="#a"/></svg>)
      )
    end

    # --- must be treated as UNEQUAL (security-relevant) ---

    def test_extra_attribute_is_unequal
      refute E.equal?(
        %(<svg xmlns="#{NS}"><rect x="1"/></svg>),
        %(<svg xmlns="#{NS}"><rect x="1" onload="alert(1)"/></svg>)
      )
    end

    def test_different_attribute_value_is_unequal
      refute E.equal?(
        %(<svg xmlns="#{NS}"><rect fill="url(#a)"/></svg>),
        %(<svg xmlns="#{NS}"><rect fill="url(#b)"/></svg>)
      )
    end

    def test_href_namespace_difference_is_unequal
      refute E.equal?(
        %(<svg xmlns="#{NS}" xmlns:xlink="#{XLINK}"><use href="#a"/></svg>),
        %(<svg xmlns="#{NS}" xmlns:xlink="#{XLINK}"><use xlink:href="#a"/></svg>)
      )
    end

    def test_element_namespace_difference_is_unequal
      refute E.equal?(
        %(<svg xmlns="#{NS}"><rect/></svg>),
        %(<svg xmlns="#{NS}" xmlns:h="urn:h"><h:rect/></svg>)
      )
    end

    def test_extra_namespace_declaration_is_unequal
      refute E.equal?(
        %(<svg xmlns="#{NS}"><rect/></svg>),
        %(<svg xmlns="#{NS}" xmlns:evil="urn:evil"><rect/></svg>)
      )
    end

    def test_extra_child_is_unequal
      refute E.equal?(
        %(<svg xmlns="#{NS}"><rect/></svg>),
        %(<svg xmlns="#{NS}"><rect/><script/></svg>)
      )
    end

    def test_child_order_is_significant
      refute E.equal?(
        %(<svg xmlns="#{NS}"><rect id="a"/><rect id="b"/></svg>),
        %(<svg xmlns="#{NS}"><rect id="b"/><rect id="a"/></svg>)
      )
    end

    def test_text_content_difference_is_unequal
      refute E.equal?(
        %(<svg xmlns="#{NS}"><title>safe</title></svg>),
        %(<svg xmlns="#{NS}"><title>evil</title></svg>)
      )
    end

    def test_text_presence_is_significant
      refute E.equal?(
        %(<svg xmlns="#{NS}"><title/></svg>),
        %(<svg xmlns="#{NS}"><title>x</title></svg>)
      )
    end
  end
end
