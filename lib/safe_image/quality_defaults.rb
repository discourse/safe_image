# frozen_string_literal: true

module SafeImage
  # Named quality defaults shared by the Ruby paths and mirrored by the native
  # helper's DEFAULT_*_QUALITY macros. Keep these values documented in one place
  # so new operations do not grow ad hoc JPEG quality choices.
  module QualityDefaults
    # Public transform default: historical safe_image behaviour and cjpegli's
    # default quality for generated JPEGs.
    JPEG = 85

    # Native convert uses ImageMagick's usual default for inputs without embedded
    # quality tables instead of libvips' lower Q75 default.
    NATIVE_CONVERT_JPEG = 92

    # fix_orientation only reaches this lossy tier when the lossless jpegtran
    # path is unavailable or rejected; keep quality high to minimize generation
    # loss while still validating a sane caller override.
    FIX_ORIENTATION_REENCODE_JPEG = 95
  end

  private_constant :QualityDefaults
end
