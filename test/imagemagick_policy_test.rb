# frozen_string_literal: true

require_relative "test_helper"

module SafeImage
  # The bundled ImageMagick security policy must refuse Ghostscript-backed
  # formats, and convert must refuse inputs and outputs outside the
  # supported image formats.
  class ImageMagickPolicyTest < TestCase
    DENIAL = /not authorized|security policy|no decode delegate/i

    POSTSCRIPT = "%!PS\n/Times-Roman findfont 12 scalefont setfont\n100 700 moveto (x) show\nshowpage\n"
    PDF =
      "%PDF-1.1\n1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj\n2 0 obj<</Type/Pages/Count 0>>endobj\ntrailer<</Root 1 0 R>>\n%%EOF\n"

    # ImageMagick reads policy.xml with a hand-rolled tokenizer, not an XML
    # parser: a backtick or apostrophe inside a comment silently drops every
    # entry after it. Assert entries from each section of the bundled file
    # survived parsing.
    def test_bundled_policy_parses_completely
      stdout, = Runner.run!([ImageMagickBackend.convert_command, "-list", "policy"])

      assert_includes stdout, "{HISTOGRAM,INFO}"
      assert_includes stdout, "{PS,PS2,PS3,EPS,EPSF,PDF,XPS,PCL,MSL,MVG,HTTPS,HTTP,URL,TEXT,LABEL}"
      assert_match(/name: memory\s+value: 512MiB/, stdout)
    end

    def test_denies_postscript_input
      ps = write_tmp("ghostscript.ps", POSTSCRIPT)
      error = assert_raises(CommandError) { Runner.run!([ImageMagickBackend.convert_command, ps, tmp_path("out.png")]) }
      assert_match DENIAL, error.stderr
    end

    def test_denies_pdf_input
      pdf = write_tmp("ghostscript.pdf", PDF)
      error =
        assert_raises(CommandError) { Runner.run!([ImageMagickBackend.convert_command, pdf, tmp_path("out.png")]) }
      assert_match DENIAL, error.stderr
    end

    def test_convert_rejects_input_that_does_not_sniff_as_an_image
      txt = write_tmp("not-image.txt", "not an image")
      assert_raises(UnsupportedFormatError) { SafeImage.convert(txt, tmp_path("sniffed.jpg"), format: "jpg") }
    end

    def test_convert_rejects_unsupported_output_format
      assert_raises(UnsupportedFormatError) { SafeImage.convert(JPG, tmp_path("bad.bmp"), format: "bmp") }
    end
  end
end
