# frozen_string_literal: true

require "tmpdir"
require_relative "../lib/discourse_image_processing"

Dir.mktmpdir do |dir|
  ps = File.join(dir, "ghostscript.ps")
  File.write(ps, "%!PS\n/Times-Roman findfont 12 scalefont setfont\n100 700 moveto (x) show\nshowpage\n")

  begin
    DiscourseImageProcessing::Runner.run!(["magick", ps, File.join(dir, "out.png")])
    abort "ImageMagick unexpectedly processed PostScript"
  rescue DiscourseImageProcessing::CommandError => e
    unless e.stderr.match?(/not authorized|security policy|no decode delegate/i)
      abort "unexpected ImageMagick denial message: #{e.stderr}"
    end
  end

  pdf = File.join(dir, "ghostscript.pdf")
  File.write(pdf, "%PDF-1.1\n1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj\n2 0 obj<</Type/Pages/Count 0>>endobj\ntrailer<</Root 1 0 R>>\n%%EOF\n")

  begin
    DiscourseImageProcessing::Runner.run!(["magick", pdf, File.join(dir, "out2.png")])
    abort "ImageMagick unexpectedly processed PDF"
  rescue DiscourseImageProcessing::CommandError => e
    unless e.stderr.match?(/not authorized|security policy|no decode delegate/i)
      abort "unexpected ImageMagick denial message: #{e.stderr}"
    end
  end

  puts "OK ImageMagick policy denies Ghostscript-backed formats"
end
