# frozen_string_literal: true

require_relative "test_helper"

module SafeImage
  class PublicApiContractTest < TestCase
    WRITING_METHODS = {
      thumbnail: %i[input output],
      optimize: %i[input output],
      resize: %i[input output],
      crop: %i[input output],
      downsize: %i[input output],
      convert: %i[input output],
      fix_orientation: %i[input output],
      convert_favicon_to_png: %i[input output],
      letter_avatar: %i[output]
    }.freeze

    def test_writing_apis_require_explicit_paths
      WRITING_METHODS.each do |method_name, required_keywords|
        parameters = SafeImage.method(method_name).parameters
        required_keywords.each do |keyword|
          assert_includes parameters, [:keyreq, keyword], "#{method_name} should require #{keyword}:"
        end
        refute_includes parameters.map(&:first), :rest, "#{method_name} should not accept positional path shuffles"
      end
    end

    def test_metadata_apis_keep_simple_path_contracts
      %i[probe type size dimensions orientation dominant_color frame_count animated?].each do |method_name|
        assert_includes SafeImage.method(method_name).parameters, %i[req path]
      end
    end

    def test_removed_legacy_mutating_convenience_apis_stay_removed
      refute_respond_to SafeImage, :optimize_image!
      refute_respond_to SafeImage, :convert_to_jpeg
    end

    def test_same_input_and_output_is_rejected_before_writing
      assert_raises(UnsafePathError) do
        SafeImage.resize(input: PNG, output: PNG, width: 16, height: 16, max_pixels: PNG_PIXELS)
      end
    end

    def test_result_contract_for_public_writer
      output = tmp_path("contract.jpg")
      result =
        SafeImage.resize(input: PNG, output: output, width: 20, height: 10, max_pixels: PNG_PIXELS, optimize: false)

      assert_equal File.expand_path(PNG), result.input
      assert_equal output, result.output
      assert_equal "jpg", result.output_format
      assert_equal [20, 10], [result.width, result.height]
      assert_operator result.duration_ms, :>=, 0
      assert_file_written output
    end
  end
end
