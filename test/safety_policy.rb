# frozen_string_literal: true

require "tmpdir"
require "zlib"
require_relative "../lib/safe_image"

FIXTURES = File.expand_path("fixtures/images", __dir__)
JPG = File.join(FIXTURES, "huge.jpg")

def png_chunk(type, data)
  [data.bytesize].pack("N") + type + data + [Zlib.crc32(type + data)].pack("N")
end

# A valid solid-grayscale PNG of arbitrary dimensions. All-zero scanlines
# compress to almost nothing, so this is a tiny file whose IHDR advertises a
# large pixel count — exactly what a decompression bomb looks like.
def solid_png(path, width, height)
  ihdr = [width, height].pack("NN") + [8, 0, 0, 0, 0].pack("C5")
  deflate = Zlib::Deflate.new
  row = "\x00".b * (width + 1)
  idat = +"".b
  height.times { idat << deflate.deflate(row) }
  idat << deflate.finish
  File.binwrite(path, "\x89PNG\r\n\x1a\n".b + png_chunk("IHDR", ihdr) + png_chunk("IDAT", idat) + png_chunk("IEND", ""))
end

Dir.mktmpdir do |dir|
  ps = File.join(dir, "ghostscript.ps")
  File.write(ps, "%!PS\n/Times-Roman findfont 12 scalefont setfont\n100 700 moveto (x) show\nshowpage\n")

  command = SafeImage::ImageMagickBackend.convert_command

  begin
    SafeImage::Runner.run!([command, ps, File.join(dir, "out.png")])
    abort "ImageMagick unexpectedly processed PostScript"
  rescue SafeImage::CommandError => e
    unless e.stderr.match?(/not authorized|security policy|no decode delegate/i)
      abort "unexpected ImageMagick denial message: #{e.stderr}"
    end
  end

  pdf = File.join(dir, "ghostscript.pdf")
  File.write(pdf, "%PDF-1.1\n1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj\n2 0 obj<</Type/Pages/Count 0>>endobj\ntrailer<</Root 1 0 R>>\n%%EOF\n")

  begin
    SafeImage::Runner.run!([command, pdf, File.join(dir, "out2.png")])
    abort "ImageMagick unexpectedly processed PDF"
  rescue SafeImage::CommandError => e
    unless e.stderr.match?(/not authorized|security policy|no decode delegate/i)
      abort "unexpected ImageMagick denial message: #{e.stderr}"
    end
  end

  puts "OK ImageMagick policy denies Ghostscript-backed formats"

  fake_dir = File.join(dir, "fake-bin")
  Dir.mkdir(fake_dir)
  fake_marker = File.join(dir, "fake-ran")
  fake_command = File.join(fake_dir, command)
  File.write(fake_command, "#!/bin/sh\ntouch #{fake_marker}\nexit 0\n")
  File.chmod(0o755, fake_command)

  begin
    SafeImage::Runner.run!(
      [command, ps, File.join(dir, "out3.png")],
      env: {
        "PATH" => fake_dir,
        "MAGICK_CONFIGURE_PATH" => "/tmp",
        "HOME" => fake_dir,
        "XDG_CACHE_HOME" => fake_dir,
        "VIPS_BLOCK_UNTRUSTED" => "0"
      }
    )
    abort "ImageMagick unexpectedly processed PostScript with env override"
  rescue SafeImage::CommandError
  end
  abort "Runner used caller-controlled PATH" if File.exist?(fake_marker)
  begin
    txt = File.join(dir, "not-image.txt")
    File.write(txt, "not an image")
    SafeImage.convert(txt, File.join(dir, "sniffed.jpg"), format: "jpg")
    abort "convert unexpectedly allowed decoder-less ImageMagick sniffing"
  rescue SafeImage::UnsupportedFormatError
  end

  begin
    SafeImage.convert(JPG, File.join(dir, "bad.bmp"), format: "bmp")
    abort "convert unexpectedly accepted unsupported format"
  rescue SafeImage::UnsupportedFormatError
  end

  puts "OK Runner ignores protected env overrides"

  begin
    SafeImage::Native.thumbnail(JPG, File.join(dir, "bad-native.jpg"), 0, 10, "jpg", 85, nil)
    abort "native thumbnail accepted zero width"
  rescue ArgumentError
  end

  begin
    SafeImage::Native.thumbnail(JPG, File.join(dir, "bad-quality.jpg"), 10, 10, "jpg", 101, nil)
    abort "native thumbnail accepted invalid quality"
  rescue ArgumentError
  end

  begin
    SafeImage::Native.resize(JPG, File.join(dir, "bad-scale.jpg"), Float::NAN, "jpg", 85, nil)
    abort "native resize accepted NaN scale"
  rescue ArgumentError
  end

  begin
    SafeImage::Native.thumbnail(JPG, File.join(dir, "bad-max.jpg"), 10, 10, "jpg", 85, 0)
    abort "native thumbnail accepted non-positive max_pixels"
  rescue ArgumentError
  end

  puts "OK native argument validation"
end

# The libvips path caps decoded pixels even when the caller passes no
# max_pixels, so a decompression bomb is rejected by default. Callers that
# legitimately need larger images opt in with an explicit max_pixels.
Dir.mktmpdir do |dir|
  bomb = File.join(dir, "bomb.png") # 12000x12000 = 144MP, above the 128MP default
  solid_png(bomb, 12_000, 12_000)

  begin
    SafeImage.thumbnail(input: bomb, output: File.join(dir, "thumb.png"), width: 32, height: 32, optimize: false)
    abort "libvips path processed a 144MP source without max_pixels"
  rescue SafeImage::LimitError
  end

  result = SafeImage.thumbnail(input: bomb, output: File.join(dir, "ok.png"), width: 32, height: 32, optimize: false, max_pixels: 200_000_000)
  abort "explicit max_pixels override was not honored" unless result.width == 32 && result.height == 32
end

puts "OK libvips enforces a default pixel cap"

# The subprocess timeout is a hard ceiling: a child that closes its standard
# streams but keeps running must still be killed at the deadline.
Dir.mktmpdir do
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  begin
    SafeImage::Runner.run!(["sh", "-c", "exec >/dev/null 2>&1; sleep 10"], timeout: 1)
    abort "Runner did not enforce the command timeout"
  rescue SafeImage::CommandError => e
    abort "Runner timeout raised the wrong error: #{e.message}" unless e.message.include?("timed out")
  end
  elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
  abort "Runner timeout not enforced (#{elapsed.round(1)}s for a 1s limit)" if elapsed > 5
end

puts "OK Runner enforces command timeout"

begin
  original = SafeImage::Sandbox.method(:available?)
  SafeImage::Sandbox.define_singleton_method(:available?) { false }
  Dir.mktmpdir do |dir|
    begin
      SafeImage.thumbnail(
        input: File.expand_path("fixtures/images/huge.jpg", __dir__),
        output: File.join(dir, "x.jpg"),
        width: 10,
        height: 10,
        execution: :sandbox
      )
      abort "strict sandbox unexpectedly fell back to inline"
    rescue SafeImage::Error => e
      abort "wrong sandbox error: #{e.message}" unless e.message.include?("sandbox execution requested")
    end
  end
ensure
  SafeImage::Sandbox.define_singleton_method(:available?, original) if original
end

puts "OK strict sandbox does not silently degrade"

Dir.mktmpdir do |dir|
  not_svg = File.join(dir, "not.svg")
  File.write(not_svg, "<html><body>nope</body></html>")
  begin
    SafeImage.sanitize_svg!(not_svg)
    abort "SVG sanitizer accepted non-SVG root"
  rescue SafeImage::InvalidImageError
  end

  svg = File.join(dir, "bad.svg")
  File.write(svg, <<~SVG)
    <svg xmlns="http://www.w3.org/2000/svg" width="10" height="10">
      <script>alert(1)</script>
      <style>@import url(http://evil.example/x.css); rect { fill: red; }</style>
      <foreignObject><iframe srcdoc="&lt;script&gt;alert(1)&lt;/script&gt;"></iframe></foreignObject>
      <image href="http://evil.example/track.png"/>
      <animate attributeName="x" from="0" to="10"/>
      <rect width="10" height="10" fill="url(http://evil.example/x)" onclick="alert(1)"/>
      <a href="javascript:alert(1)"><text>bad</text></a>
      <use href="#safe"/>
      <circle id="safe" r="2" fill="url(#safe)"/>
      <!-- <script>alert(1)</script> -->
      <text><![CDATA[<script>alert(1)</script>&xss;]]></text>
    </svg>
  SVG
  SafeImage.sanitize_svg!(svg)
  cleaned = File.read(svg)
  abort "SVG sanitizer kept script element/text" if cleaned.match?(/<script/i)
  abort "SVG sanitizer kept style element" if cleaned.match?(/<style/i)
  abort "SVG sanitizer kept foreignObject" if cleaned.match?(/foreignObject/i)
  abort "SVG sanitizer kept iframe/object/embed/image" if cleaned.match?(/<(?:iframe|object|embed|image)\b/i)
  abort "SVG sanitizer kept animation" if cleaned.match?(/<animate/i)
  abort "SVG sanitizer kept external url" if cleaned.include?("evil.example")
  abort "SVG sanitizer kept event handler" if cleaned.include?("onclick")
  abort "SVG sanitizer kept javascript href" if cleaned.match?(/javascript/i)
  abort "SVG sanitizer stripped fragment href" unless cleaned.include?("href='#safe'") || cleaned.include?("href=\"#safe\"")
  abort "SVG sanitizer stripped fragment url" unless cleaned.include?("url(#safe)")
  abort "SVG sanitizer kept comment" if cleaned.include?("<!--")
  abort "SVG sanitizer kept CDATA" if cleaned.include?("CDATA")
  abort "SVG sanitizer failed to escape text" unless cleaned.include?("&lt;script&gt;") && cleaned.include?("&amp;xss;")

  encoded_url_svg = File.join(dir, "encoded-url.svg")
  File.write(encoded_url_svg, <<~SVG)
    <svg xmlns="http://www.w3.org/2000/svg" width="10" height="10">
      <rect width="10" height="10" fill="url(&#104;ttp://evil.example/x)"/>
      <a href="jav&#x61;script:alert(1)"><text>bad</text></a>
    </svg>
  SVG
  SafeImage.sanitize_svg!(encoded_url_svg)
  encoded_cleaned = File.read(encoded_url_svg)
  abort "SVG sanitizer kept entity-encoded URL" if encoded_cleaned.include?("evil.example")
  abort "SVG sanitizer kept entity-encoded javascript" if encoded_cleaned.match?(/javascript/i)

  dtd_entity_svg = File.join(dir, "dtd-entity.svg")
  File.write(dtd_entity_svg, <<~SVG)
    <?xml version="1.0"?>
    <!DOCTYPE svg [ <!ENTITY xss "<script>alert(1)</script>"> ]>
    <svg xmlns="http://www.w3.org/2000/svg" width="10" height="10">
      <text>&xss;</text>
    </svg>
  SVG
  begin
    SafeImage.sanitize_svg!(dtd_entity_svg)
    abort "SVG sanitizer accepted DTD entity payload"
  rescue SafeImage::InvalidImageError
  end

  huge_svg = File.join(dir, "huge.svg")
  File.write(huge_svg, '<svg xmlns="http://www.w3.org/2000/svg" width="100000" height="100000"></svg>')
  begin
    SafeImage.sanitize_svg!(huge_svg)
    abort "SVG sanitizer accepted huge dimensions"
  rescue SafeImage::LimitError
  end
end

puts "OK SVG sanitizer rejects non-SVG roots and external URLs"