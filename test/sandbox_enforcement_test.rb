# frozen_string_literal: true

require_relative "test_helper"

module SafeImage
  # Strict (:sandbox) execution must raise when the Landlock sandbox is
  # unavailable rather than silently degrading to inline execution.
  #
  # The landlock gem is not part of the default bundle, so the sandbox is
  # genuinely unavailable here and in CI — no stubbing needed. When landlock
  # is bundled, the unavailable path cannot be reached honestly, so this
  # skips and SandboxIntegrationTest covers the sandbox instead.
  class SandboxEnforcementTest < TestCase
    def test_strict_execution_does_not_fall_back_to_inline
      skip "Landlock sandbox is available, so the unavailable path cannot be exercised" if SafeImage.sandbox_available?

      error = assert_raises(Error) do
        SafeImage.thumbnail(input: JPG, output: tmp_path("x.jpg"), width: 10, height: 10, execution: :sandbox)
      end
      assert_includes error.message, "sandbox execution requested"
    end
  end
end
