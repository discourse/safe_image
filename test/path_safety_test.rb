# frozen_string_literal: true

require_relative "test_helper"

module SafeImage
  class PathSafetyTest < TestCase
    def test_rejects_symlink_input
      link = tmp_path("input.jpg")
      File.symlink(JPG, link)

      assert_raises(UnsafePathError) { SafeImage.probe(link) }
    end

    def test_rejects_symlink_output_and_leaves_its_target_untouched
      victim = write_tmp("victim.jpg", "victim")
      output = tmp_path("out.jpg")
      File.symlink(victim, output)

      assert_raises(UnsafePathError) do
        SafeImage.thumbnail(input: JPG, output: output, width: 10, height: 10)
      end
      assert_equal "victim", File.read(victim), "symlink output target changed"
    end

    def test_rejects_output_under_symlinked_directory
      outside = tmp_path("outside")
      Dir.mkdir(outside)
      subdir = tmp_path("subdir")
      File.symlink(outside, subdir)

      assert_raises(UnsafePathError) do
        SafeImage.thumbnail(input: JPG, output: File.join(subdir, "out.jpg"), width: 10, height: 10)
      end
    end

    # Relative input paths are expanded to absolute before processing, so the
    # ImageMagick-backed helpers accept them just like the rest of the API.
    def test_accepts_relative_input_paths
      Dir.chdir(FIXTURES) do
        assert_kind_of Integer, SafeImage.orientation("huge.jpg")
        assert_kind_of Integer, SafeImage.frame_count("huge.jpg", max_pixels: JPG_PIXELS)
        refute SafeImage.animated?("huge.jpg", max_pixels: JPG_PIXELS)
      end
    end
  end
end
