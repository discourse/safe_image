# frozen_string_literal: true

require_relative "test_helper"

module SafeImage
  class RunnerTest < TestCase
    POSTSCRIPT = "%!PS\n/Times-Roman findfont 12 scalefont setfont\n100 700 moveto (x) show\nshowpage\n"

    # Caller-supplied env must not be able to redirect PATH to a fake binary
    # or weaken the hardened ImageMagick/libvips configuration.
    def test_ignores_caller_controlled_environment_overrides
      command = ImageMagickBackend.convert_command
      fake_bin = tmp_path("fake-bin")
      Dir.mkdir(fake_bin)
      marker = tmp_path("fake-ran")
      File.write(File.join(fake_bin, command), "#!/bin/sh\ntouch #{marker}\nexit 0\n")
      File.chmod(0o755, File.join(fake_bin, command))

      ps = write_tmp("ghostscript.ps", POSTSCRIPT)
      error =
        assert_raises(CommandError) do
          Runner.run!(
            [command, ps, tmp_path("out.png")],
            env: {
              "PATH" => fake_bin,
              "MAGICK_CONFIGURE_PATH" => "/tmp",
              "HOME" => fake_bin,
              "XDG_CACHE_HOME" => fake_bin,
              "VIPS_BLOCK_UNTRUSTED" => "0"
            }
          )
        end
      assert_equal :exit_status, error.category
      refute_path_exists marker, "Runner used caller-controlled PATH"
    end

    # The subprocess timeout is a hard ceiling: a child that closes its
    # standard streams but keeps running must still be killed at the deadline.
    def test_enforces_command_timeout
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      error = assert_raises(CommandError) { Runner.run!(["sh", "-c", "exec >/dev/null 2>&1; sleep 10"], timeout: 1) }
      assert_includes error.message, "timed out"
      assert_equal :timeout, error.category

      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
      assert_operator elapsed, :<, 5, "timeout not enforced (#{elapsed.round(1)}s for a 1s limit)"
    end
  end
end
