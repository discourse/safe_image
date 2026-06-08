# frozen_string_literal: true

require "tmpdir"
require_relative "../lib/safe_image"

PNG = File.expand_path("fixtures/images/large_and_unoptimized.png", __dir__)
JPG = File.expand_path("fixtures/images/huge.jpg", __dir__)
HEIC = File.expand_path("fixtures/images/should_be_jpeg.heic", __dir__)

def jpeg?(path)
  File.binread(path, 3) == "\xFF\xD8\xFF".b
end

Dir.mktmpdir do |dir|
  forced_missing = File.join(dir, "missing.jpg")
  original_available = SafeImage::JpegliBackend.method(:available?)
  SafeImage::JpegliBackend.define_singleton_method(:available?) { false }
  begin
    begin
      SafeImage.convert(PNG, forced_missing, format: "jpg", encoder: :cjpegli)
      abort "encoder: :cjpegli did not fail when cjpegli was unavailable"
    rescue SafeImage::UnsupportedFormatError
    end
  ensure
    SafeImage::JpegliBackend.define_singleton_method(:available?, original_available)
  end

  fallback = File.join(dir, "fallback.jpg")
  SafeImage.convert(PNG, fallback, format: "jpg", encoder: :imagemagick, quality: 85, max_pixels: 10_000_000)
  raise "imagemagick fallback did not create JPEG" unless jpeg?(fallback)

  unless SafeImage::JpegliBackend.available?
    warn "SKIP cjpegli integration: cjpegli is not installed"
    next
  end

  converted = File.join(dir, "converted.jpg")
  result = SafeImage.convert(PNG, converted, format: "jpg", encoder: :cjpegli, quality: 85, max_pixels: 10_000_000)
  raise "cjpegli convert did not report backend" unless result.backend == "cjpegli"
  raise "cjpegli convert did not create JPEG" unless jpeg?(converted)
  raise "wrong convert type" unless SafeImage.type(converted, max_pixels: 10_000_000) == :jpeg

  auto = File.join(dir, "auto.jpg")
  auto_result = SafeImage.convert(PNG, auto, format: "jpg", quality: 85, max_pixels: 10_000_000)
  raise "auto did not select cjpegli for direct PNG input" unless auto_result.backend == "cjpegli"

  heic = File.join(dir, "heic.jpg")
  begin
    heic_result = SafeImage.convert(HEIC, heic, format: "jpg", quality: 85, encoder: :auto, max_pixels: 10_000_000)
    raise "auto should fall back for HEIC, got #{heic_result.backend}" if heic_result.backend == "cjpegli"
  rescue SafeImage::Error => e
    warn "SKIP HEIC fallback conversion: #{e.message}"
  end

  begin
    SafeImage.convert(HEIC, File.join(dir, "bad-heic.jpg"), format: "jpg", encoder: :cjpegli, max_pixels: 10_000_000)
    abort "forced cjpegli accepted unsupported HEIC direct input"
  rescue SafeImage::UnsupportedFormatError
  end

  thumb = File.join(dir, "thumb.jpg")
  thumb_result = SafeImage.thumbnail(input: JPG, output: thumb, width: 320, height: 200, encoder: :cjpegli, max_pixels: 100_000_000)
  raise "cjpegli thumbnail did not report backend" unless thumb_result.backend.include?("cjpegli")
  raise "wrong thumbnail dimensions" unless thumb_result.width == 320 && thumb_result.height == 200
  raise "thumbnail not JPEG" unless jpeg?(thumb)

  crop = File.join(dir, "crop.jpg")
  crop_result = SafeImage.crop(JPG, crop, 200, 160, backend: :vips, encoder: :cjpegli, max_pixels: 100_000_000)
  raise "cjpegli crop did not report backend" unless crop_result.backend.include?("cjpegli")
  raise "wrong crop dimensions" unless crop_result.width == 200 && crop_result.height == 160
  raise "crop not JPEG" unless jpeg?(crop)

  down = File.join(dir, "down.jpg")
  down_result = SafeImage.downsize(PNG, down, "320x200>", backend: :vips, encoder: :cjpegli, max_pixels: 10_000_000)
  raise "cjpegli downsize did not report backend" unless down_result.backend.include?("cjpegli")
  raise "downsize not JPEG" unless jpeg?(down)

  png_source_thumb = File.join(dir, "thumb-from-png.jpg")
  png_thumb = SafeImage.thumbnail(input: PNG, output: png_source_thumb, width: 320, height: 200, encoder: :cjpegli, chroma_subsampling: :auto, max_pixels: 10_000_000)
  raise "PNG-source thumbnail did not report backend" unless png_thumb.backend.include?("cjpegli")
  raise "PNG-source thumbnail not JPEG" unless jpeg?(png_source_thumb)

  begin
    SafeImage.thumbnail(input: JPG, output: File.join(dir, "bad-thumb.jpg"), width: 10, height: 10, backend: :imagemagick, encoder: :cjpegli, max_pixels: 100_000_000)
    abort "forced cjpegli thumbnail accepted non-vips backend"
  rescue ArgumentError
  end
end

puts "OK cjpegli integration"
