# frozen_string_literal: true

require "fileutils"
require_relative "test_helper"

module SafeImage
  class ContentFormatTest < TestCase
    SUPPORTED_FIXTURES = { JPG => "jpg", PNG => "png", GIF => "gif", WEBP => "webp", JXL => "jxl", ICO => "ico" }.freeze

    def test_detect_identifies_every_supported_fixture
      SUPPORTED_FIXTURES.each { |path, format| assert_equal format, SafeImage.detect_format(path), File.basename(path) }

      assert_equal "heic", SafeImage.detect_format(HEIC)
    end

    def test_detect_ignores_the_extension
      png_named_jpg = misnamed(PNG, "photo.jpg")
      jpeg_named_png = misnamed(JPG, "photo.png")

      assert_equal "png", SafeImage.detect_format(png_named_jpg)
      assert_equal "jpg", SafeImage.detect_format(jpeg_named_png)
    end

    def test_isobmff_brands_are_read_past_the_major_brand
      avif = write_tmp("generic.avif", "\x00\x00\x00\x18ftypmif1\x00\x00\x00\x00mif1avif")
      heic = write_tmp("generic.heic", "\x00\x00\x00\x14ftypheic\x00\x00\x00\x00heic")
      mp4 = write_tmp("video.mp4", "\x00\x00\x00\x14ftypisom\x00\x00\x00\x00isom")

      assert_equal "avif", SafeImage.detect_format(avif)
      assert_equal "heic", SafeImage.detect_format(heic)
      assert_nil SafeImage.detect_format(mp4)
    end

    def test_bare_heif_brands_report_heif
      heif = write_tmp("photo.heif", "\x00\x00\x00\x14ftypmif1\x00\x00\x00\x00mif1")

      assert_equal "heif", SafeImage.detect_format(heif)
    end

    def test_detect_reads_both_jxl_framings
      naked_codestream = write_tmp("naked.jxl", "\xFF\x0A#{"\0" * 16}")

      assert_equal "jxl", SafeImage.detect_format(naked_codestream)
      assert_equal "jxl", SafeImage.detect_format(JXL)
    end

    def test_detect_returns_nil_for_bytes_it_cannot_identify
      unrecognised = write_tmp("mystery.png", "not an image")
      truncated = write_tmp("truncated.png", "\x89P")
      empty = write_tmp("empty.png", "")

      assert_nil SafeImage.detect_format(unrecognised)
      assert_nil SafeImage.detect_format(truncated)
      assert_nil SafeImage.detect_format(empty)
    end

    def test_detects_svg_under_any_name
      svg = write_tmp("icon.svg", '<svg xmlns="http://www.w3.org/2000/svg" width="4" height="6"></svg>')
      misnamed_svg = write_tmp("logo.png", '<svg xmlns="http://www.w3.org/2000/svg" width="4" height="6"></svg>')

      assert_equal "svg", SafeImage.detect_format(svg)
      assert_equal "svg", SafeImage.detect_format(misnamed_svg)
      assert_equal :svg, SafeImage.type(misnamed_svg)
      assert_equal [4, 6], SafeImage.size(misnamed_svg)
    end

    def test_detects_svg_behind_a_declaration_comments_and_a_doctype
      svg = write_tmp("verbose.svg", <<~XML)
        <?xml version="1.0" encoding="UTF-8"?>
        <!-- exported by a drawing tool -->
        <!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd">
        <svg xmlns="http://www.w3.org/2000/svg" width="8" height="9"></svg>
      XML

      assert_equal "svg", SafeImage.detect_format(svg)
    end

    def test_does_not_call_arbitrary_markup_svg
      html = write_tmp("page.html", "<html><body><svg width='1' height='1'></svg></body></html>")
      prose = write_tmp("notes.txt", "an <svg> tag is mentioned here")

      assert_nil SafeImage.detect_format(html)
      assert_nil SafeImage.detect_format(prose)
    end

    def test_probe_reports_the_content_format_on_both_backends
      each_backend do |backend|
        png_named_jpg = misnamed(PNG, "probe-#{backend}.jpg")

        result = SafeImage.probe(png_named_jpg, max_pixels: PNG_PIXELS)

        assert_equal "png", result.input_format, "#{backend} probe"
        assert_equal [2032, 1312], [result.width, result.height], "#{backend} dimensions"
      end
    end

    def test_type_and_info_report_the_content_format
      png_named_jpg = misnamed(PNG, "photo.jpg")

      assert_equal :png, SafeImage.type(png_named_jpg, max_pixels: PNG_PIXELS)
      assert_equal :png, SafeImage.info(png_named_jpg, max_pixels: PNG_PIXELS).type
      assert_equal [2032, 1312], SafeImage.size(png_named_jpg, max_pixels: PNG_PIXELS)
    end

    def test_thumbnail_decodes_png_bytes_named_jpg
      each_backend do |backend|
        png_named_jpg = misnamed(PNG, "thumb-#{backend}.jpg")

        result =
          SafeImage.thumbnail(
            input: png_named_jpg,
            output: tmp_path("thumb-#{backend}.png"),
            width: 40,
            height: 20,
            max_pixels: PNG_PIXELS
          )

        assert_equal "png", result.input_format, "#{backend} input format"
        assert_result result, width: 40, height: 20, format: "png"
      end
    end

    def test_resize_and_convert_decode_jpeg_bytes_named_png
      jpeg = tmp_path("source.jpg")
      SafeImage.thumbnail(input: PNG, output: jpeg, width: 120, height: 80, max_pixels: PNG_PIXELS)

      each_backend do |backend|
        jpeg_named_png = misnamed(jpeg, "photo-#{backend}.png")

        resize =
          SafeImage.resize(
            input: jpeg_named_png,
            output: tmp_path("resized-#{backend}.jpg"),
            width: 60,
            height: 40,
            optimize: false
          )
        convert =
          SafeImage.convert(
            input: jpeg_named_png,
            output: tmp_path("converted-#{backend}.png"),
            format: "png",
            optimize: false
          )

        assert_result resize, width: 60, height: 40, format: "jpg"
        assert_jpeg_magic resize.output
        assert_result convert, width: 120, height: 80, format: "png"
      end
    end

    def test_optimize_follows_the_content_not_the_name
      png_named_jpg = misnamed(PNG, "photo.jpg")

      result = SafeImage.optimize(input: png_named_jpg, output: tmp_path("optimized.png"))

      assert_equal "png", result.fetch(:format)
      refute_empty result.fetch(:tools)
    end

    def test_dominant_color_and_animation_checks_follow_the_content
      each_backend do |backend|
        gif_named_png = misnamed(GIF, "clip-#{backend}.png")

        assert SafeImage.animated?(gif_named_png), "#{backend} should see the animated GIF"
        assert_match(/\A\h{6}\z/, SafeImage.dominant_color(gif_named_png), "#{backend} dominant color")
      end
    end

    def test_ico_bytes_are_recognised_under_any_name
      each_backend do |backend|
        ico_named_png = misnamed(ICO, "favicon-#{backend}.png")

        result = SafeImage.convert_favicon_to_png(input: ico_named_png, output: tmp_path("favicon-#{backend}-out.png"))

        assert_equal "ico", SafeImage.probe(ico_named_png).input_format, "#{backend} probe"
        assert_result result, width: 1, height: 1, format: "png"
      end
    end

    def test_unidentifiable_bytes_still_fail_closed
      assert_raises(InvalidImageError) { SafeImage.probe(write_tmp("broken.png", "not an image")) }

      each_backend do |backend|
        assert_raises(Error, backend.to_s) { SafeImage.probe(write_tmp("broken-#{backend}.png", "not an image")) }
        assert_raises(UnsupportedFormatError, backend.to_s) do
          SafeImage.probe(write_tmp("notes-#{backend}.txt", "not an image"))
        end
      end
    end

    def test_formats_this_gem_cannot_decode_are_refused_by_content
      bmp_named_png = write_tmp("bitmap.png", "BM#{"\0" * 30}")

      assert_nil SafeImage.detect_format(bmp_named_png)
      assert_raises(Error) { SafeImage.probe(bmp_named_png) }
    end

    private

    def misnamed(fixture, name)
      tmp_path(name).tap { |path| FileUtils.cp(fixture, path) }
    end

    def each_backend
      %i[vips imagemagick].each do |backend|
        configure_safe_image(backend: backend)
        yield backend
      end
    end
  end
end
