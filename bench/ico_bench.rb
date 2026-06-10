# frozen_string_literal: true

# Benchmarks the pure-Ruby ICO path against the ImageMagick compatibility
# backend. Run with: bundle exec ruby bench/ico_bench.rb

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "safe_image"
require "tmpdir"

module IcoBench
  FAVICON = File.expand_path("../test/fixtures/images/favicon.ico", __dir__)
  SMALLEST = File.expand_path("../test/fixtures/images/smallest.ico", __dir__)

  def self.bench(label, iterations)
    # warm up
    2.times { yield }
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    iterations.times { yield }
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    puts format("%-46s %10.3f ms/call  (%d iterations)", label, elapsed / iterations * 1000, iterations)
  end

  def self.run
    data, entries = SafeImage::Ico.parse(FAVICON)
    largest = SafeImage::Ico.largest(entries)
    small_entry = entries.min_by { |e| e.width * e.height }

    Dir.mktmpdir("ico-bench-") do |dir|
      out = File.join(dir, "out.png")

      puts "== directory metadata (probe) =="
      bench("Ico.probe (4 entries)", 2_000) { SafeImage::Ico.probe(FAVICON) }
      bench("ImageMagick identify probe", 50) { SafeImage::ImageMagickBackend.probe(FAVICON) }

      puts "\n== DIB decode to RGBA (pure Ruby hot loop) =="
      bench("decode_rgba 256x256 32bpp", 50) { SafeImage::Ico.decode_rgba(data, largest) }
      bench("decode_rgba 16x16 32bpp", 2_000) { SafeImage::Ico.decode_rgba(data, small_entry) }

      puts "\n== favicon -> png end to end =="
      bench("Ico.convert_to_png 256x256", 50) { SafeImage::Ico.convert_to_png(FAVICON, out) }
      bench("Ico.convert_to_png 1x1", 200) { SafeImage::Ico.convert_to_png(SMALLEST, out) }
      bench("ImageMagick convert_ico_to_png 256x256", 20) do
        SafeImage::ImageMagickBackend.convert_ico_to_png(input: FAVICON, output: out)
      end
    end
  end
end

IcoBench.run
