# frozen_string_literal: true

require_relative "test_helper"

module SafeImage
  # The bundled ImageMagick security policy must refuse Ghostscript-backed
  # formats, and convert must refuse inputs and outputs outside the
  # supported image formats.
  class ImageMagickPolicyTest < TestCase
    DENIAL = /not authorized|security policy|no decode delegate/i

    POSTSCRIPT = "%!PS\n/Times-Roman findfont 12 scalefont setfont\n100 700 moveto (x) show\nshowpage\n"
    PDF = "%PDF-1.1\n1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj\n2 0 obj<</Type/Pages/Count 0>>endobj\ntrailer<</Root 1 0 R>>\n%%EOF\n"

    def test_denies_postscript_input
      ps = write_tmp("ghostscript.ps", POSTSCRIPT)
      error = assert_raises(CommandError) do
        Runner.run!([ImageMagickBackend.convert_command, ps, tmp_path("out.png")])
      end
      assert_match DENIAL, error.stderr
    end

    def test_denies_pdf_input
      pdf = write_tmp("ghostscript.pdf", PDF)
      error = assert_raises(CommandError) do
        Runner.run!([ImageMagickBackend.convert_command, pdf, tmp_path("out.png")])
      end
      assert_match DENIAL, error.stderr
    end

    def test_convert_rejects_input_that_does_not_sniff_as_an_image
      txt = write_tmp("not-image.txt", "not an image")
      assert_raises(UnsupportedFormatError) do
        SafeImage.convert(txt, tmp_path("sniffed.jpg"), format: "jpg")
      end
    end

    def test_convert_rejects_unsupported_output_format
      assert_raises(UnsupportedFormatError) do
        SafeImage.convert(JPG, tmp_path("bad.bmp"), format: "bmp")
      end
    end
  end
end
