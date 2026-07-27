# frozen_string_literal: true

module SafeImage
  module ContentFormat
    module_function

    HEAD_BYTES = 4096

    PNG_MAGIC = "\x89PNG\r\n\x1A\n".b.freeze
    JPEG_MAGIC = "\xFF\xD8\xFF".b.freeze
    GIF_MAGICS = ["GIF87a".b.freeze, "GIF89a".b.freeze].freeze
    ICO_MAGIC = "\x00\x00\x01\x00".b.freeze
    JXL_CODESTREAM_MAGIC = "\xFF\x0A".b.freeze
    JXL_CONTAINER_MAGIC = "\x00\x00\x00\x0CJXL \r\n\x87\n".b.freeze
    RIFF_MAGIC = "RIFF".b.freeze
    WEBP_MAGIC = "WEBP".b.freeze
    FTYP_MAGIC = "ftyp".b.freeze

    AVIF_BRANDS = %w[avif avis].map { |brand| brand.b.freeze }.freeze
    HEIC_BRANDS = %w[heic heix heim heis hevc hevx hevm hevs].map { |brand| brand.b.freeze }.freeze
    HEIF_BRANDS = %w[mif1 msf1].map { |brand| brand.b.freeze }.freeze

    UTF8_BOM = "\uFEFF"
    SVG_ROOT_PATTERN =
      /
        \A
        (?:<\?xml[^>]*>\s*)?
        (?:<!--.*?-->\s*)*
        (?:<!doctype\s+svg\b[^>]*(?:\[[\s\S]*?\]\s*)?>\s*)?
        (?:<!--.*?-->\s*)*
        <svg(?:\s|>)
      /mx

    private_constant :HEAD_BYTES,
                     :PNG_MAGIC,
                     :JPEG_MAGIC,
                     :GIF_MAGICS,
                     :ICO_MAGIC,
                     :JXL_CODESTREAM_MAGIC,
                     :JXL_CONTAINER_MAGIC,
                     :RIFF_MAGIC,
                     :WEBP_MAGIC,
                     :FTYP_MAGIC,
                     :AVIF_BRANDS,
                     :HEIC_BRANDS,
                     :HEIF_BRANDS,
                     :UTF8_BOM,
                     :SVG_ROOT_PATTERN

    def detect(path)
      path = PathSafety.ensure_regular_file!(path).to_s
      detect_head(File.binread(path, HEAD_BYTES).to_s)
    end

    def for_input(path)
      detect(path) || Formats.extension(path)
    end

    def detect_head(head)
      head = head.b
      return "png" if head.start_with?(PNG_MAGIC)
      return "jpg" if head.start_with?(JPEG_MAGIC)
      return "gif" if GIF_MAGICS.any? { |magic| head.start_with?(magic) }
      return "webp" if head.start_with?(RIFF_MAGIC) && head.byteslice(8, 4) == WEBP_MAGIC
      return "jxl" if head.start_with?(JXL_CONTAINER_MAGIC) || head.start_with?(JXL_CODESTREAM_MAGIC)
      return "ico" if head.start_with?(ICO_MAGIC)

      isobmff_format(head) || svg_format(head)
    end

    def isobmff_format(head)
      return nil unless head.byteslice(4, 4) == FTYP_MAGIC

      brands = isobmff_brands(head)
      return "avif" if brands.any? { |brand| AVIF_BRANDS.include?(brand) }
      return "heic" if brands.any? { |brand| HEIC_BRANDS.include?(brand) }
      return "heif" if brands.any? { |brand| HEIF_BRANDS.include?(brand) }

      nil
    end

    def svg_format(head)
      text = head.encode("UTF-8", invalid: :replace, undef: :replace).delete_prefix(UTF8_BOM).lstrip.downcase
      "svg" if SVG_ROOT_PATTERN.match?(text)
    end

    def isobmff_brands(head)
      box_size = head.byteslice(0, 4).unpack1("N").to_i
      limit = [box_size.positive? ? box_size : head.bytesize, head.bytesize].min
      brands = [head.byteslice(8, 4)]
      offset = 16
      while offset + 4 <= limit
        brands << head.byteslice(offset, 4)
        offset += 4
      end
      brands.compact
    end

    private_class_method :detect_head, :isobmff_format, :isobmff_brands, :svg_format
  end

  private_constant :ContentFormat
end
